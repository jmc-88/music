/*-
 * Copyright (c) 2011-2012	   Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

using Gtk;
using Gee;
using Notify;

public class BeatBox.LibraryWindow : LibraryWindowInterface, Gtk.Window {
	public static Granite.Application app { get; private set; }

	public BeatBox.LibraryManager lm;
	BeatBox.Settings settings;
	LastFM.SimilarMedias similarMedias;
	BeatBox.MediaKeyListener mkl;

	HashMap<int, Device> welcome_screen_keys;
	bool queriedlastfm; // whether or not we have queried last fm for the current media info
	bool media_considered_played; //whether or not we have updated last played and added to already played list
	bool added_to_play_count; // whether or not we have added one to play count on playing media
	bool tested_for_video; // whether or not we have tested if media is video and shown video
	bool scrobbled_track;
	LinkedList<string> timeout_search;//stops from doing useless search
	string last_search;//stops from searching same thing multiple times

	public bool dragging_from_music;
	public bool millerVisible;
	bool askToSetFolder;

	public bool initializationFinished;

	VBox verticalBox;
	public VBox mainViews;
	public MillerColumns miller;
	HPaned millerPane;
	BeatBox.Welcome welcomeScreen;
	public DrawingArea videoArea;
	public HPaned sourcesToMedias; //allows for draggable
	HPaned mediasToInfo; // media info pane
	ScrolledWindow sideTreeScroll;
	VBox sideBar;
	VBox contentBox;
	public SideTreeView sideTree;
	ScrolledWindow mediaInfoScroll;
	ScrolledWindow pandoraScroll;
	ScrolledWindow grooveSharkScroll;
	InfoPanel infoPanel;
	Toolbar topControls;
	ToolButton previousButton;
	ToolButton playButton;
	ToolButton nextButton;
	public TopDisplay topDisplay;
	public Granite.Widgets.ModeButton viewSelector;
	public Granite.Widgets.SearchBar searchField;

	StatusBar statusBar;

	SimpleOptionChooser addPlaylistChooser;
	SimpleOptionChooser shuffleChooser;
	SimpleOptionChooser repeatChooser;
	SimpleOptionChooser infoPanelChooser;

	// we use one album list view popup for the whole app
	public AlbumListView alv;

	// basic file stuff
	ImageMenuItem libraryOperations;
	Gtk.Menu libraryOperationsMenu;
	Gtk.MenuItem fileSetMusicFolder;
	Gtk.MenuItem fileImportMusic;
	Gtk.MenuItem fileRescanMusicFolder;
	Gtk.MenuItem editEqualizer;
	ImageMenuItem editPreferences;

	// Base color
	public static Gdk.RGBA BASE_COLOR;

	Gtk.Menu settingsMenu;

	public Notify.Notification notification;

	public signal void playPauseChanged();

	public LibraryWindow(Granite.Application app, BeatBox.Settings settings, string[] args) {
		this.app = app;
		this.settings = settings;

		//this is used by many objects, is the media backend
		lm = new BeatBox.LibraryManager(settings, this, args);

		//various objects
		welcome_screen_keys = new HashMap<int, Device>();
		similarMedias = new LastFM.SimilarMedias(lm);
		timeout_search = new LinkedList<string>();
		mkl = new MediaKeyListener(lm, this);
		last_search = "";

#if HAVE_INDICATE
#if HAVE_DBUSMENU
		message("Initializing MPRIS and sound menu\n");
		var mpris = new BeatBox.MPRIS(lm, this);
		mpris.initialize();
#endif
#endif

		dragging_from_music = false;
		askToSetFolder = false;

		this.lm.player.end_of_stream.connect(end_of_stream);
		this.lm.player.current_position_update.connect(current_position_update);
		//this.lm.player.media_not_found.connect(media_not_found);
		this.lm.music_counted.connect(musicCounted);
		this.lm.music_added.connect(musicAdded);
		this.lm.music_imported.connect(musicImported);
		this.lm.music_rescanned.connect(musicRescanned);
		this.lm.progress_notification.connect(progressNotification);
		this.lm.medias_added.connect(medias_added);
		this.lm.medias_updated.connect(medias_updated);
		this.lm.medias_removed.connect(medias_removed);
		this.lm.media_played.connect(media_played);
		this.lm.playback_stopped.connect(playback_stopped);
		this.lm.dm.device_added.connect(device_added);
		this.lm.dm.device_removed.connect(device_removed);
		this.similarMedias.similar_retrieved.connect(similarRetrieved);

		destroy.connect (on_quit);
		check_resize.connect(on_resize);
		this.destroy.connect (Gtk.main_quit);

		if(lm.media_count() == 0 && settings.getMusicFolder() == "") {
			message("First run.\n");
		}
		else {
			lm.clearCurrent();
			//((MusicTreeView)sideTree.getWidget(sideTree.library_music_iter)).set_as_current_list("0");

			// make sure we don't re-count stats
			if((int)settings.getLastMediaPosition() > 5)
				queriedlastfm = true;
			if((int)settings.getLastMediaPosition() > 30)
				media_considered_played = true;
			if(lm.media_info.media != null && (double)((int)settings.getLastMediaPosition()/(double)lm.media_info.media.length) > 0.90)
				added_to_play_count = true;

			// rescan on startup
			/*lm.rescan_music_folder();*/
		}

		/*if(!File.new_for_path(settings.getMusicFolder()).query_exists() && settings.getMusicFolder() != "") {
			doAlert("Music folder not mounted", "Your music folder is not mounted. Please mount your music folder before using BeatBox.");
		}*/
	}

	public void build_ui() {
		// simple message to terminal
		message ("Building user interface\n");

		// Load icon information
		Icons.load ();

		// Setup base color
		var unused_icon_view = new IconView();
		var base_style = unused_icon_view.get_style_context();
		base_style.add_class (Gtk.STYLE_CLASS_VIEW);
		BASE_COLOR = base_style.get_background_color(StateFlags.NORMAL);
		unused_icon_view.destroy();

		// set the size based on saved gconf settings
		set_default_size(settings.getWindowWidth(), settings.getWindowHeight());
		resize(settings.getWindowWidth(), settings.getWindowHeight());

		// set window min/max
		Gdk.Geometry geo = Gdk.Geometry();
		geo.min_width = 700;
		geo.min_height = 400;
		set_geometry_hints(this, geo, Gdk.WindowHints.MIN_SIZE);

		// set the title
		set_title("BeatBox");

		// set the icon
		set_icon(Icons.BEATBOX_ICON.render (IconSize.MENU, null));

		/* Initialize all components */
		verticalBox = new VBox(false, 0);
		sourcesToMedias = new HPaned();
		mediasToInfo = new HPaned();
		contentBox = new VBox(false, 0);
		millerPane = new HPaned();
		mainViews = new VBox(false, 0);
		videoArea = new DrawingArea();
		welcomeScreen = new Welcome(_("Get Some Tunes"), _("BeatBox can't seem to find your music."));

		sideTree = new SideTreeView(lm, this);
		sideTreeScroll = new ScrolledWindow(null, null);
		libraryOperations = new ImageMenuItem.from_stock("library-music", null);
		libraryOperationsMenu = new Gtk.Menu();
		fileSetMusicFolder = new Gtk.MenuItem.with_label(_("Set Music Folder"));
		fileImportMusic = new Gtk.MenuItem.with_label(_("Import to Library"));
		fileRescanMusicFolder = new Gtk.MenuItem.with_label(_("Rescan Music Folder"));
		editEqualizer = new Gtk.MenuItem.with_label(_("Equalizer"));
		editPreferences = new ImageMenuItem.from_stock(Gtk.Stock.PREFERENCES, null);
		settingsMenu = new Gtk.Menu();
		topControls = new Toolbar();
		previousButton = new ToolButton.from_stock(Gtk.Stock.MEDIA_PREVIOUS);
		playButton = new ToolButton.from_stock(Gtk.Stock.MEDIA_PLAY);
		nextButton = new ToolButton.from_stock(Gtk.Stock.MEDIA_NEXT);
		topDisplay = new TopDisplay(lm);
		viewSelector = new Granite.Widgets.ModeButton();
		searchField = new Granite.Widgets.SearchBar(_("Search..."));
		miller = new MillerColumns(lm, this); //miller must be below search for it to work properly
		mediaInfoScroll = new ScrolledWindow(null, null);
		pandoraScroll = new ScrolledWindow(null, null);
		grooveSharkScroll = new ScrolledWindow(null, null);
		infoPanel = new InfoPanel(lm, this);
		sideBar = new VBox(false, 0);
		statusBar = new StatusBar();
		alv = new AlbumListView(lm);

		var add_playlist_image = Icons.render_image ("list-add-symbolic", IconSize.MENU);
		var shuffle_on_image = Icons.SHUFFLE_ON_ICON.render_image (IconSize.MENU);
		var shuffle_off_image = Icons.SHUFFLE_OFF_ICON.render_image (IconSize.MENU);
		var repeat_on_image = Icons.REPEAT_ON_ICON.render_image (IconSize.MENU);
		var repeat_off_image = Icons.REPEAT_OFF_ICON.render_image (IconSize.MENU);
		var info_panel_show = Icons.PANE_SHOW_SYMBOLIC.render_image (IconSize.MENU);
		var info_panel_hide = Icons.PANE_HIDE_SYMBOLIC.render_image (IconSize.MENU);

		addPlaylistChooser = new SimpleOptionChooser.from_image (add_playlist_image);
		shuffleChooser = new SimpleOptionChooser.from_image (shuffle_on_image, shuffle_off_image);
		repeatChooser = new SimpleOptionChooser.from_image (repeat_on_image, repeat_off_image);
		infoPanelChooser = new SimpleOptionChooser.from_image (info_panel_hide, info_panel_show);

		infoPanelChooser.setTooltip (_("Hide Info Panel"), _("Show Info Panel"));
		addPlaylistChooser.setTooltip (_("Add Playlist"));

		statusBar.insert_widget (addPlaylistChooser as Gtk.Widget, true);
		statusBar.insert_widget (new Gtk.Box (Orientation.HORIZONTAL, 12), true);
		statusBar.insert_widget (shuffleChooser as Gtk.Widget, true);
		statusBar.insert_widget (repeatChooser as Gtk.Widget, true);
		statusBar.insert_widget (infoPanelChooser as Gtk.Widget);

		notification = (Notify.Notification)GLib.Object.new (
						typeof (Notify.Notification),
						"summary", _("Title"),
						"body", "%s\n%s".printf(_("Artist"), _("Album")));

		/* Set properties of various controls */
		//sideBar.set_size_request(200, -1);
		sourcesToMedias.set_position(settings.getSidebarWidth());
		mediasToInfo.set_position((lm.settings.getWindowWidth() - lm.settings.getSidebarWidth()) - lm.settings.getMoreWidth());

		//for setting maximum size for setting hpane position max size
		//sideBar.set_geometry_hints(

		debug ("building side tree\n");
		buildSideTree();
		debug ("done with side tree\n");

		sideTreeScroll = new ScrolledWindow(null, null);
		sideTreeScroll.set_policy (PolicyType.AUTOMATIC, PolicyType.AUTOMATIC);
		sideTreeScroll.add(sideTree);

		millerPane.set_position(settings.getMillerWidth());

		updateSensitivities();

		/* create appmenu menu */
		libraryOperationsMenu.append(fileSetMusicFolder);
		libraryOperationsMenu.append(fileImportMusic);
		libraryOperationsMenu.append(fileRescanMusicFolder);
		libraryOperations.submenu = libraryOperationsMenu;
		libraryOperations.set_label(_("Library"));

		settingsMenu.append(libraryOperations);
		settingsMenu.append(new SeparatorMenuItem());
		settingsMenu.append(editEqualizer);
		settingsMenu.append(editPreferences);

		fileSetMusicFolder.activate.connect(editPreferencesClick);
		fileImportMusic.activate.connect(fileImportMusicClick);
		fileRescanMusicFolder.activate.connect(fileRescanMusicFolderClick);

		editPreferences.set_label(_("Preferences"));

		editEqualizer.activate.connect(editEqualizerClick);
		editPreferences.activate.connect(editPreferencesClick);

		repeatChooser.appendItem(_("Off"));
		repeatChooser.appendItem(_("Song"));
		repeatChooser.appendItem(_("Album"));
		repeatChooser.appendItem(_("Artist"));
		repeatChooser.appendItem(_("All"));

		shuffleChooser.appendItem(_("Off"));
		shuffleChooser.appendItem(_("All"));

		infoPanelChooser.appendItem(_("Hide"));
		infoPanelChooser.appendItem(_("Show"));

		repeatChooser.setOption(settings.getRepeatMode());
		shuffleChooser.setOption(settings.getShuffleMode());
		infoPanelChooser.setOption(settings.getMoreVisible() ? 1 : 0);

		/* Add controls to the GUI */
		add(verticalBox);
		verticalBox.pack_start(topControls, false, true, 0);
		verticalBox.pack_start(videoArea, true, true, 0);
		verticalBox.pack_start(sourcesToMedias, true, true, 0);
		verticalBox.pack_end(statusBar, false, true, 0);

		ToolItem topDisplayBin = new ToolItem();
		ToolItem viewSelectorBin = new ToolItem();
		ToolItem searchFieldBin = new ToolItem();

		// FIXME: Ugly workaround to make the view-mode button smaller
		var viewSelectorContainer = new Box (Orientation.VERTICAL, 0);
		var viewSelectorInnerContainer = new Box (Orientation.HORIZONTAL, 0);
		viewSelectorInnerContainer.pack_start (new Box (Orientation.HORIZONTAL, 10), true, true, 0);
		viewSelectorInnerContainer.pack_start (viewSelector, false, false, 0); // VIEW SELECTOR
		viewSelectorInnerContainer.pack_end (new Box (Orientation.HORIZONTAL, 10), true, true, 0);
		viewSelectorContainer.pack_start (new Box (Orientation.VERTICAL, 5), true, true, 0);
		viewSelectorContainer.pack_start (viewSelectorInnerContainer, false, false, 0);
		viewSelectorContainer.pack_end (new Box (Orientation.VERTICAL, 5), true, true, 0);

		topDisplayBin.add(topDisplay);
		topDisplayBin.set_border_width(1);
		topDisplayBin.margin_left = 12;

		viewSelectorBin.add(viewSelectorContainer);
		viewSelectorBin.margin_left = 12;

		searchFieldBin.add(searchField);
		searchFieldBin.margin_left = 12;
		searchFieldBin.margin_right = 12;

		topDisplayBin.set_expand(true);

		// Set theming
		topControls.get_style_context().add_class("primary-toolbar");
		sourcesToMedias.get_style_context().add_class("sidebar-pane-separator");
		sideTree.get_style_context().add_class("sidebar");

		viewSelector.append(Icons.VIEW_ICONS_ICON.render_image (IconSize.MENU));
		viewSelector.append(Icons.VIEW_DETAILS_ICON.render_image (IconSize.MENU));
		viewSelector.append(Icons.VIEW_COLUMN_ICON.render_image (IconSize.MENU));

		topControls.insert(previousButton, 0);
		topControls.insert(playButton, 1);
		topControls.insert(nextButton, 2);
		topControls.insert(viewSelectorBin, 3);
		topControls.insert(topDisplayBin, 4);
		topControls.insert(searchFieldBin, 5);
		topControls.insert(app.create_appmenu(settingsMenu), 6);

		// for consistency
		topControls.set_size_request(-1, 45);

		contentBox.pack_start(welcomeScreen, true, true, 0);

		var music_folder_icon = Icons.MUSIC_FOLDER.render (IconSize.DIALOG, null);
		welcomeScreen.append_with_pixbuf(music_folder_icon, _("Locate"), _("Change your music folder."));

		millerPane.pack1(miller, false, true);
		millerPane.pack2(mainViews, true, true);

		contentBox.pack_start(millerPane, true, true, 0);

		mediasToInfo.pack1(contentBox, true, true);
		mediasToInfo.pack2(infoPanel, false, false);

		sourcesToMedias.pack1(sideBar, false, true);
		sourcesToMedias.pack2(mediasToInfo, true, true);

		sideBar.pack_start(sideTreeScroll, true, true, 0);

		// add mounts to side tree view
		lm.dm.loadPreExistingMounts();

		/* Connect events to functions */
		sourcesToMedias.get_child1().size_allocate.connect(sourcesToMediasHandleSet);
		welcomeScreen.activated.connect(welcomeScreenActivated);
		previousButton.clicked.connect(previousClicked);
		playButton.clicked.connect(playClicked);
		nextButton.clicked.connect(nextClicked);
		infoPanel.size_allocate.connect(infoPanelResized);

		addPlaylistChooser.button_press_event.connect(addPlaylistChooserOptionClicked);
		repeatChooser.option_changed.connect(repeatChooserOptionChanged);
		shuffleChooser.option_changed.connect(shuffleChooserOptionChanged);
		infoPanelChooser.option_changed.connect(infoPanelChooserOptionChanged);

		viewSelector.mode_changed.connect(updateMillerColumns);
		viewSelector.mode_changed.connect( () => { updateSensitivities(); } );
		millerPane.get_child1().size_allocate.connect(millerResized);
		miller.changed.connect(millerChanged);
		searchField.changed.connect(searchFieldChanged);
		searchField.activate.connect(searchFieldActivate);

		/* set up drag dest stuff */
		drag_dest_set(this, DestDefaults.ALL, {}, Gdk.DragAction.MOVE);
		Gtk.drag_dest_add_uri_targets(this);
		drag_data_received.connect(dragReceived);

		viewSelector.selected = settings.getViewMode();

		int i = settings.getLastMediaPlaying();
		if(i != 0 && lm.media_from_id(i) != null && File.new_for_uri(lm.media_from_id(i).uri).query_exists()) {
			lm.media_from_id(i).resume_pos;
			lm.playMedia(i, true);
		}
		else {
			// don't show info panel if nothing playing
			infoPanel.set_visible(false);
		}

		initializationFinished = true;

		sideTree.resetView();
		var vw = (ViewWrapper)sideTree.getSelectedWidget();
		if(lm.media_info.media != null) {
			vw.list.set_as_current_list(0, true);
			debug ("set a view as current list\n");
			if(settings.getShuffleMode() == LibraryManager.Shuffle.ALL) {
				lm.setShuffleMode(LibraryManager.Shuffle.ALL, true);
			}
		}

		searchField.set_text(lm.settings.getSearchString());
		//vw.doUpdate(vw.currentView, vw.get_media_ids(), false, true, false);

		show_all();
		resize(settings.getWindowWidth(), this.default_height);

		updateSensitivities();

		if(lm.song_ids().size == 0)
			setMusicFolder(Environment.get_user_special_dir(UserDirectory.MUSIC));
	}

	public static Gtk.Alignment wrap_alignment (Gtk.Widget widget, int top, int right, int bottom, int left) {
		var alignment = new Gtk.Alignment(0.0f, 0.0f, 1.0f, 1.0f);
		alignment.top_padding = top;
		alignment.right_padding = right;
		alignment.bottom_padding = bottom;
		alignment.left_padding = left;

		alignment.add(widget);
		return alignment;
	}

	/** Builds the side tree on TreeView view
	 * @param view The side tree to build it on : TODO
	 */
	private void buildSideTree() {
		ViewWrapper vw;

		sideTree.addBasicItems();

		vw = new ViewWrapper(lm, this, new LinkedList<int>(), lm.similar_setup.sort_column, lm.similar_setup.sort_direction, ViewWrapper.Hint.SIMILAR, -1);
		sideTree.addSideItem(sideTree.playlists_iter, null, vw, _("Similar"), ViewWrapper.Hint.SIMILAR);
		mainViews.pack_start(vw, true, true, 0);

		vw = new ViewWrapper(lm, this, lm.queue(), lm.queue_setup.sort_column, lm.queue_setup.sort_direction, ViewWrapper.Hint.QUEUE, -1);
		sideTree.addSideItem(sideTree.playlists_iter, null, vw, _("Queue"), ViewWrapper.Hint.QUEUE);
		mainViews.pack_start(vw, true, true, 0);

		vw = new ViewWrapper(lm, this, lm.already_played(), lm.history_setup.sort_column, lm.history_setup.sort_direction, ViewWrapper.Hint.HISTORY, -1);
		sideTree.addSideItem(sideTree.playlists_iter, null, vw, _("History"), ViewWrapper.Hint.HISTORY);
		mainViews.pack_start(vw, true, true, 0);

		vw = new ViewWrapper(lm, this, lm.media_ids(), lm.music_setup.sort_column, lm.music_setup.sort_direction, ViewWrapper.Hint.MUSIC, -1);
		sideTree.addSideItem(sideTree.library_iter, null, vw, _("Music"), ViewWrapper.Hint.MUSIC);
		mainViews.pack_start(vw, true, true, 0);

		vw = new ViewWrapper(lm, this, lm.podcast_ids(), "", 0, ViewWrapper.Hint.PODCAST, -1);
		sideTree.addSideItem(sideTree.library_iter, null, vw, _("Podcasts"), ViewWrapper.Hint.PODCAST);
		mainViews.pack_start(vw, true, true, 0);

		vw = new ViewWrapper(lm, this, lm.station_ids(), lm.station_setup.sort_column, lm.station_setup.sort_direction, ViewWrapper.Hint.STATION, -1);
		sideTree.addSideItem(sideTree.network_iter, null, vw, _("Internet Radio"), ViewWrapper.Hint.STATION);
		mainViews.pack_start(vw, true, true, 0);

		if(Option.enable_store) {
			Store.StoreView storeView = new Store.StoreView(lm, this);
			sideTree.addSideItem(sideTree.network_iter, null, storeView, _("Music Store"), ViewWrapper.Hint.NONE);
			mainViews.pack_start(storeView, true, true, 0);
		}

		// load smart playlists
		foreach(SmartPlaylist p in lm.smart_playlists()) {
			addSideListItem(p);
		}

		// load playlists
		foreach(Playlist p in lm.playlists()) {
			addSideListItem(p);
		}
	}

	public void addSideListItem(GLib.Object o) {
		TreeIter item = sideTree.library_music_iter; //just a default
		ViewWrapper vw = null;

		if(o is Playlist) {
			Playlist p = (Playlist)o;

			vw = new ViewWrapper(lm, this, lm.medias_from_playlist(p.rowid), p.tvs.sort_column, p.tvs.sort_direction, ViewWrapper.Hint.PLAYLIST, p.rowid);
			item = sideTree.addSideItem(sideTree.playlists_iter, p, vw, p.name, ViewWrapper.Hint.PLAYLIST);
			mainViews.pack_start(vw, true, true, 0);
		}
		else if(o is SmartPlaylist) {
			SmartPlaylist p = (SmartPlaylist)o;

			vw = new ViewWrapper(lm, this, lm.medias_from_smart_playlist(p.rowid), p.tvs.sort_column, p.tvs.sort_direction, ViewWrapper.Hint.SMART_PLAYLIST, p.rowid);
			item = sideTree.addSideItem(sideTree.playlists_iter, p, vw, p.name, ViewWrapper.Hint.SMART_PLAYLIST);
			mainViews.pack_start(vw, true, true, 0);
		}
		else if(o is Device) {
			Device d = (Device)o;

			if(d.getContentType() == "cdrom") {
				vw = new DeviceViewWrapper(lm, this, d.get_medias(), "Track", Gtk.SortType.ASCENDING, ViewWrapper.Hint.CDROM, -1, d);
				item = sideTree.addSideItem(sideTree.devices_iter, d, vw, d.getDisplayName(), ViewWrapper.Hint.CDROM);
				mainViews.pack_start(vw, true, true, 0);
			}
			else {
				debug ("adding ipod device view with %d\n", d.get_medias().size);
				DeviceView dv = new DeviceView(lm, d);
				//vw = new DeviceViewWrapper(lm, this, d.get_medias(), "Artist", Gtk.SortType.ASCENDING, ViewWrapper.Hint.DEVICE, -1, d);
				item = sideTree.addSideItem(sideTree.devices_iter, d, dv, d.getDisplayName(), ViewWrapper.Hint.NONE);
				mainViews.pack_start(dv, true, true, 0);
			}
		}

		if(vw == null || vw.list == null || vw.albumView == null)
			return;

		if(!initializationFinished)
			return;

		vw.show_all();
		if(viewSelector.selected == 0) {
			vw.albumView.show();
			vw.list.hide();
		}
		else {
			vw.list.show();
			vw.albumView.hide();
		}
	}

	public void updateSensitivities() {
		if(!initializationFinished)
			return;

		bool folderSet = (lm.settings.getMusicFolder() != "");
		bool haveMedias = lm.media_count() > 0;
		bool haveSongs = lm.song_ids().size > 0;
		bool doingOps = lm.doing_file_operations();
		bool nullMedia = (lm.media_info.media == null);
		bool showMore = lm.settings.getMoreVisible();

		bool showingMediaList = (sideTree.getSelectedWidget() is ViewWrapper);
		bool songsInList = showingMediaList ? (((ViewWrapper)sideTree.getSelectedWidget()).media_count > 0) : false;
		bool showingMusicList = sideTree.convertToChild(sideTree.getSelectedIter()) == sideTree.library_music_iter;
		bool showMainViews = (haveSongs || (haveMedias &&!showingMusicList));

		fileSetMusicFolder.set_sensitive(!doingOps);
		fileImportMusic.set_sensitive(!doingOps && folderSet);
		fileRescanMusicFolder.set_sensitive(!doingOps && folderSet);

		if(doingOps)
			topDisplay.show_progressbar();
		else if(!nullMedia && lm.media_info.media.mediatype == 3) {
			topDisplay.hide_scale_and_progressbar();
		}
		else
			topDisplay.show_scale();

		sourcesToMedias.set_visible(viewSelector.selected != 3);
		videoArea.set_visible(viewSelector.selected == 3);

		topDisplay.set_visible(!nullMedia || doingOps);
		topDisplay.set_scale_sensitivity(!nullMedia);

		previousButton.set_sensitive(!nullMedia || songsInList);
		playButton.set_sensitive(!nullMedia || songsInList);
		nextButton.set_sensitive(!nullMedia || songsInList);
		searchField.set_sensitive(showingMediaList && songsInList && showMainViews);
		viewSelector.set_sensitive(showingMediaList);

		mainViews.set_visible(showMainViews);
		miller.set_visible((showMainViews) && viewSelector.selected == 2 && showingMediaList);
		welcomeScreen.set_visible(!showMainViews);
		millerPane.set_visible(showMainViews);

		welcomeScreen.set_sensitivity(0, !doingOps);
		foreach(int key in welcome_screen_keys.keys)
			welcomeScreen.set_sensitivity(key, !doingOps);

		statusBar.set_visible(showMainViews && showingMediaList);

		infoPanel.set_visible(showMainViews && showMore && !nullMedia);
		infoPanelChooser.set_visible(showMainViews && !nullMedia);

		// hide playlists when media list is empty
		sideTree.setVisibility(sideTree.playlists_iter, haveMedias);

		if(lm.media_info.media == null || haveMedias && !lm.playing) {
			playButton.set_stock_id(Gtk.Stock.MEDIA_PLAY);
		}
	}

	public virtual void progressNotification(string? message, double progress) {
		if(message != null && progress >= 0.0 && progress <= 1.0)
			topDisplay.set_label_markup(message);

		topDisplay.set_progress_value(progress);
	}

	public void updateInfoLabel() {
		if(lm.doing_file_operations()) {
			debug ("doing file operations, returning null in updateInfoLabel\n");
			return;
		}

		if(lm.media_info.media == null) {
			topDisplay.set_label_markup("");
			debug ("setting info label as ''\n");
			return;
		}

		string beg = "";
		if(lm.media_info.media.mediatype == 3) // radio
			beg = "<b>" + lm.media_info.media.album_artist.replace("\n", "") + "</b>\n";

		//set the title
		Media s = lm.media_info.media;
		var title = "<b>" + s.title.replace("&", "&amp;") + "</b>";
		var artist = ((s.artist != "" && s.artist != _("Unknown Artist")) ? (_(" by ") + "<b>" + s.artist.replace("&", "&amp;") + "</b>") : "");
		var album = ((s.album != "" && s.album != _("Unknown Album")) ? (_(" on ") + "<b>" + s.album.replace("&", "&amp;") + "</b>") : "");

		var media_label = beg + title + artist + album;
		topDisplay.set_label_markup(media_label);
	}

	/** This should be used whenever a call to play a new media is made
	 * @param s The media that is now playing
	 */
	public virtual void media_played(int i, int old) {
		/*if(old == -2 && i != -2) { // -2 is id reserved for previews
			Media s = settings.getLastMediaPlaying();
			s = lm.media_from_name(s.title, s.artist);

			if(s.rowid != 0) {
				lm.playMedia(s.rowid);
				int position = (int)settings.getLastMediaPosition();
				topDisplay.change_value(ScrollType.NONE, position);
			}

			return;
		}*/

		updateInfoLabel();

		//reset the media position
		topDisplay.set_scale_sensitivity(true);
		topDisplay.set_scale_range(0.0, lm.media_info.media.length);

		if(lm.media_from_id(i).mediatype == 1 || lm.media_from_id(i).mediatype == 2) {
			/*message("setting position to resume_pos which is %d\n", lm.media_from_id(i).resume_pos );
			Timeout.add(250, () => {
				topDisplay.change_value(ScrollType.NONE, lm.media_from_id(i).resume_pos);
				return false;
			});*/
		}
		else {
			topDisplay.change_value(ScrollType.NONE, 0);
		}

		//if(!mediaPosition.get_sensitive())
		//	mediaPosition.set_sensitive(true);

		//reset some booleans
		tested_for_video = false;
		queriedlastfm = false;
		media_considered_played = false;
		added_to_play_count = false;
		scrobbled_track = false;

		if(!lm.media_info.media.isPreview) {
			infoPanel.updateMedia(lm.media_info.media.rowid);
			if(settings.getMoreVisible())
				infoPanel.set_visible(true);

			updateMillerColumns();
		}

		updateSensitivities();

		// if radio, we can't depend on current_position_update. do that stuff now.
		if(lm.media_info.media.mediatype == 3) {
			queriedlastfm = true;
			similarMedias.queryForSimilar(lm.media_info.media);

			try {
				Thread.create<void*>(lastfm_track_thread_function, false);
				Thread.create<void*>(lastfm_album_thread_function, false);
				Thread.create<void*>(lastfm_artist_thread_function, false);
				Thread.create<void*>(lastfm_update_nowplaying_thread_function, false);
			}
			catch(GLib.ThreadError err) {
				warning ("ERROR: Could not create last fm thread: %s \n", err.message);
			}

			// always show notifications for the radio, since user likely does not know media
			mkl.showNotification(lm.media_info.media.rowid);
		}
	}

	public virtual void playback_stopped(int was_playing) {
		//reset some booleans
		tested_for_video = false;
		queriedlastfm = false;
		media_considered_played = false;
		added_to_play_count = false;

		updateSensitivities();

		debug ("stopped\n");
	}

	public virtual void medias_updated(Collection<int> ids) {
		if(lm.media_info.media != null && ids.contains(lm.media_info.media.rowid)) {
			updateInfoLabel();
		}
	}

	void medias_added(LinkedList<int> ids) {
		/*var new_songs = new LinkedList<int>();
		var new_podcasts = new LinkedList<int>();

		foreach(int i in ids) {
			if(lm.media_from_id(i).mediatype == 0)
				new_songs.add(i);
			else if(lm.media_from_id(i).mediatype == 1)
				new_podcasts.add(i);
		}

		message("appending...\n");
		ViewWrapper vw = (ViewWrapper)sideTree.getWidget(sideTree.library_music_iter);
		vw.add_medias(new_songs);

		vw = (ViewWrapper)sideTree.getWidget(sideTree.library_podcasts_iter);
		vw.add_medias(new_podcasts);
		message("appended\n");*/

		var w = sideTree.getSelectedWidget();
		if(w is ViewWrapper) {
			miller.populateColumns("", ((ViewWrapper)w).get_media_ids());
		}

		updateSensitivities();
	}

	public void* lastfm_track_thread_function () {
		LastFM.TrackInfo track = new LastFM.TrackInfo.basic();

		string artist_s = lm.media_info.media.artist;
		string track_s = lm.media_info.media.title;

		/* first fetch track info since that is most likely to change */
		if(!lm.track_info_exists(track_s + " by " + artist_s)) {
			track = new LastFM.TrackInfo.with_info(artist_s, track_s);

			if(track != null)
				lm.save_track(track);

			if(track_s == lm.media_info.media.title && artist_s == lm.media_info.media.artist)
				lm.media_info.track = track;
		}

		return null;
	}

	public void* lastfm_album_thread_function () {
		LastFM.AlbumInfo album = new LastFM.AlbumInfo.basic();

		string artist_s = lm.media_info.media.artist;
		string album_s = lm.media_info.media.album;

		/* fetch album info now. only save if still on current media */
		if(!lm.album_info_exists(album_s + " by " + artist_s) || lm.get_cover_album_art(lm.media_info.media.rowid) == null) {
			album = new LastFM.AlbumInfo.with_info(artist_s, album_s);

			if(album != null)
				lm.save_album(album);

			/* make sure we save image to right location (user hasn't changed medias) */
			if(lm.media_info.media != null && album != null && album_s == lm.media_info.media.album &&
			artist_s == lm.media_info.media.artist && lm.media_info.media.getAlbumArtPath().contains("media-audio.png")) {
				lm.media_info.album = album;

				if (album.url_image.url != null && lm.settings.getUpdateFolderHierarchy()) {
					lm.save_album_locally(lm.media_info.media.rowid, album.url_image.url);

					// start thread to load all the medias pixbuf's
					try {
						Thread.create<void*>(lm.fetch_thread_function, false);
					}
					catch(GLib.ThreadError err) {
						warning("Could not create thread to load media pixbuf's: %s \n", err.message);
					}
				}
			}
			else {
				return null;
			}
		}

		return null;
	}

	public void* lastfm_artist_thread_function () {
		LastFM.ArtistInfo artist = new LastFM.ArtistInfo.basic();

		string artist_s = lm.media_info.media.artist;

		/* fetch artist info now. save only if still on current media */
		if(!lm.artist_info_exists(artist_s)) {
			artist = new LastFM.ArtistInfo.with_artist(artist_s);

			if(artist != null)
				lm.save_artist(artist);

			//try to save artist art locally
			if(lm.media_info.media != null && artist != null && artist_s == lm.media_info.media.artist &&
			!File.new_for_path(lm.media_info.media.getArtistImagePath()).query_exists()) {
				lm.media_info.artist = artist;

			}
			else {
				return null;
			}
		}

		Idle.add( () => { infoPanel.updateCoverArt(true); return false;});

		return null;
	}

	public void* lastfm_update_nowplaying_thread_function() {
		if(lm.media_info.media != null) {
			lm.lfm.updateNowPlaying(lm.media_info.media.title, lm.media_info.media.artist);
		}

		return null;
	}

	public void* lastfm_scrobble_thread_function () {
		if(lm.media_info.media != null) {
			lm.lfm.scrobbleTrack(lm.media_info.media.title, lm.media_info.media.artist);
		}

		return null;
	}

	public bool updateMediaInfo() {
		infoPanel.updateMedia(lm.media_info.media.rowid);

		return false;
	}

	public virtual void previousClicked () {
		if(lm.player.getPosition() < 5000000000 || (lm.media_info.media != null && lm.media_info.media.mediatype == 3)) {
			int prev_id = lm.getPrevious(true);

			/* test to stop playback/reached end */
			if(prev_id == 0) {
				lm.player.pause();
				lm.playing = false;
				updateSensitivities();
				return;
			}
		}
		else
			topDisplay.change_value(ScrollType.NONE, 0);
	}

	public virtual void playClicked () {
		if(lm.media_info.media == null) {
			debug("No media is currently playing. Starting from the top\n");
			//set current medias by current view
			Widget w = sideTree.getSelectedWidget();
			if(w is ViewWrapper) {
				((ViewWrapper)w).list.set_as_current_list(1, true);
			}
			else {
				w = sideTree.getWidget(sideTree.library_music_iter);
				((ViewWrapper)w).list.set_as_current_list(1, true);
			}

			lm.getNext(true);

			lm.playing = true;
			playButton.set_stock_id(Gtk.Stock.MEDIA_PAUSE);
			lm.player.play();
		}
		else {
			if(lm.playing) {
				lm.playing = false;
				lm.player.pause();

				playButton.set_stock_id(Gtk.Stock.MEDIA_PLAY);
			}
			else {
				lm.playing = true;
				lm.player.play();
				playButton.set_stock_id(Gtk.Stock.MEDIA_PAUSE);
			}
		}

		playPauseChanged();
	}

	public virtual void nextClicked() {
		// if not 90% done, skip it
		if(!added_to_play_count) {
			lm.media_info.media.skip_count++;

			// don't update, it will be updated eventually
			//lm.update_media(lm.media_info.media, false, false);
		}

		int next_id;
		if(lm.next_gapless_id != 0) {
			next_id = lm.next_gapless_id;
			lm.playMedia(lm.next_gapless_id, false);
		}
		else
			next_id = lm.getNext(true);

		/* test to stop playback/reached end */
		if(next_id == 0) {
			lm.player.pause();
			lm.playing = false;
			updateSensitivities();
			return;
		}
	}

	public virtual void loveButtonClicked() {
		lm.lfm.loveTrack(lm.media_info.media.title, lm.media_info.media.artist);
	}

	public virtual void banButtonClicked() {
		lm.lfm.banTrack(lm.media_info.media.title, lm.media_info.media.artist);
	}

	public virtual void searchFieldIconPressed(EntryIconPosition p0, Gdk.Event p1) {
		Widget w = sideTree.getSelectedWidget();
		w.focus(DirectionType.UP);
	}

	public virtual void millerResized(Allocation rectangle) {
		if(viewSelector.selected == 2) {
			settings.setMillerWidth(rectangle.width);
		}
	}

	public virtual void sourcesToMediasHandleSet(Allocation rectangle) {
		if(settings.getSidebarWidth() != rectangle.width) {
			settings.setSidebarWidth(rectangle.width);
		}
	}

	public virtual void on_resize() {
		int width;
		int height;
		this.get_size(out width, out height);
		settings.setWindowWidth(width);
		settings.setWindowHeight(height);
	}

	public virtual void on_quit() {
		lm.settings.setLastMediaPosition((int)((double)lm.player.getPosition()/1000000000));
		if(lm.media_info.media != null) {
			lm.media_info.media.resume_pos = (int)((double)lm.player.getPosition()/1000000000);
			lm.update_media(lm.media_info.media, false, false);
		}
		lm.player.pause();
	}

	public virtual void fileImportMusicClick() {
		if(!lm.doing_file_operations()) {
			/*if(!(GLib.File.new_for_path(lm.settings.getMusicFolder()).query_exists() && lm.settings.getCopyImportedMusic())) {
				var dialog = new MessageDialog(this, DialogFlags.DESTROY_WITH_PARENT, MessageType.ERROR, ButtonsType.OK,
				"Before importing, you must mount your music folder.");

				var result = dialog.run();
				dialog.destroy();

				return;
			}*/

			string folder = "";
			var file_chooser = new FileChooserDialog (_("Import Music"), this,
									  FileChooserAction.SELECT_FOLDER,
									  Gtk.Stock.CANCEL, ResponseType.CANCEL,
									  Gtk.Stock.OPEN, ResponseType.ACCEPT);
			file_chooser.set_local_only(true);

			if (file_chooser.run () == ResponseType.ACCEPT) {
				folder = file_chooser.get_filename();
			}
			file_chooser.destroy ();

			if(folder != "" && folder != settings.getMusicFolder()) {
				if(GLib.File.new_for_path(lm.settings.getMusicFolder()).query_exists()) {
					topDisplay.set_label_markup(_("<b>Importing</b> music from <b>%s</b> to library.").printf(folder));
					topDisplay.show_progressbar();

					lm.add_folder_to_library(folder);
					updateSensitivities();
				}
			}
		}
		else {
			debug("Can't add to library.. already doing file operations\n");
		}
	}

	public virtual void fileRescanMusicFolderClick() {
		if(!lm.doing_file_operations()) {
			if(GLib.File.new_for_path(this.settings.getMusicFolder()).query_exists()) {
				topDisplay.set_label_markup("<b>" + _("Rescanning music folder for changes") + "</b>");
				topDisplay.show_progressbar();

				lm.rescan_music_folder();
				updateSensitivities();
			}
			else {
				doAlert(_("Could not find Music Folder"), _("Please make sure that your music folder is accessible and mounted."));
			}
		}
		else {
			debug("Can't rescan.. doing file operations already\n");
		}
	}

	public void resetSideTree(bool clear_views) {
		sideTree.resetView();

		// clear all other playlists, reset to Music, populate music
		if(clear_views) {
			debug("clearing all views...\n");
			mainViews.get_children().foreach( (w) => {
				if(w is ViewWrapper/* && !(w is CDRomViewWrapper)*/ && !(w is DeviceViewWrapper)) {
					ViewWrapper vw = (ViewWrapper)w;
					debug("doing clear\n");
					vw.doUpdate(vw.currentView, new LinkedList<int>(), true, true, false);
					debug("cleared\n");
				}
			});
			debug("all cleared\n");
		}
		else {
			ViewWrapper vw = (ViewWrapper)sideTree.getWidget(sideTree.library_music_iter);
			vw.doUpdate(vw.currentView, lm.song_ids(), true, true, false);
			miller.populateColumns("", lm.song_ids());

			vw = (ViewWrapper)sideTree.getWidget(sideTree.library_podcasts_iter);
			vw.doUpdate(vw.currentView, lm.podcast_ids(), true, true, false);

			//vw = (ViewWrapper)sideTree.getWidget(sideTree.library_audiobooks_iter);
			//vw.doUpdate(vw.currentView, lm.audiobook_ids(), true, true, false);

			vw = (ViewWrapper)sideTree.getWidget(sideTree.network_radio_iter);
			vw.doUpdate(vw.currentView, lm.station_ids(), true, true, false);
		}
	}

	public virtual void musicCounted(int count) {
		debug ("found %d medias, importing.\n", count);
	}

	/* this is after setting the music library */
	public virtual void musicAdded(LinkedList<string> not_imported) {

		if(lm.media_info.media != null) {
			updateInfoLabel();
		}
		else
			topDisplay.set_label_text("");

		//resetSideTree(false);
		//var init = searchField.get_text();
		//searchField.set_text("up");

		if(not_imported.size > 0) {
			NotImportedWindow nim = new NotImportedWindow(this, not_imported, lm.settings.getMusicFolder());
			nim.show();
		}

		updateSensitivities();

		//now notify user
		try {
			notification.close();
			if(!has_toplevel_focus) {
				notification.update(_("Import Complete"), _("BeatBox has imported your library."), "beatbox");

				notification.set_image_from_pixbuf(Icons.BEATBOX_DIALOG_PIXBUF);

				notification.show();
				notification.set_timeout(5000);
			}
		}
		catch(GLib.Error err) {
			stderr.printf("Could not show notification: %s\n", err.message);
		}
	}

	/* this is when you import music from a foreign location into the library */
	public virtual void musicImported(LinkedList<Media> new_medias, LinkedList<string> not_imported) {
		if(lm.media_info.media != null) {
			updateInfoLabel();
		}
		else
			topDisplay.set_label_text("");

		resetSideTree(false);
		//searchField.changed();

		updateSensitivities();
	}

	public virtual void musicRescanned(LinkedList<Media> new_medias, LinkedList<string> not_imported) {
		if(lm.media_info.media != null) {
			updateInfoLabel();
		}
		else
			topDisplay.set_label_text("");

		resetSideTree(false);
		//searchField.changed();
		debug("music Rescanned\n");
		updateSensitivities();
	}

	public virtual void medias_removed(LinkedList<int> removed) {
		updateSensitivities();
	}

	public void editEqualizerClick() {
		EqualizerWindow ew = new EqualizerWindow(lm, this);
		ew.show();
	}

	public void editPreferencesClick() {
		PreferencesWindow pw = new PreferencesWindow(lm, this);

		pw.changed.connect( (folder) => {
			setMusicFolder(folder);
		});
	}

	public void setMusicFolder(string folder) {
		if(lm.doing_file_operations())
			return;

		if(lm.song_ids().size > 0 || lm.playlist_count() > 0) {
			var smfc = new SetMusicFolderConfirmation(lm, this, folder);
			smfc.finished.connect( (cont) => {
				if(cont) {
					lm.set_music_folder(folder);
				}
			});
		}
		else {
			lm.set_music_folder(folder);
		}
	}

	public virtual void end_of_stream() {
		nextClicked();
	}

	public virtual void current_position_update(int64 position) {
		if(lm.media_info.media != null && lm.media_info.media.rowid == -2) // is preview
			return;

		double sec = 0.0;
		if(lm.media_info.media != null) {
			sec = ((double)position/1000000000);

			if(lm.player.set_resume_pos) {
				lm.media_info.media.resume_pos = (int)sec;
			}

			// at about 3 seconds, update last fm. we wait to avoid excessive querying last.fm for info
			if(position > 3000000000 && !queriedlastfm) {
				queriedlastfm = true;

				ViewWrapper vw = (ViewWrapper)sideTree.getWidget(sideTree.playlists_similar_iter);
				if(!vw.list.get_is_current()) {
					vw.show_retrieving_similars();
					similarMedias.queryForSimilar(lm.media_info.media);
				}

				try {
					Thread.create<void*>(lastfm_track_thread_function, false);
					Thread.create<void*>(lastfm_album_thread_function, false);
					Thread.create<void*>(lastfm_artist_thread_function, false);
					Thread.create<void*>(lastfm_update_nowplaying_thread_function, false);
				}
				catch(GLib.ThreadError err) {
					warning("ERROR: Could not create last fm thread: %s \n", err.message);
				}
			}

			//at 30 seconds in, we consider the media as played
			if(position > 30000000000 && !media_considered_played) {
				media_considered_played = true;

				lm.media_info.media.last_played = (int)time_t();
				if(lm.media_info.media.mediatype == 1) { //podcast
					added_to_play_count = true;
					++lm.media_info.media.play_count;
				}
				lm.update_media(lm.media_info.media, false, false);

				// add to the already played list
				lm.add_already_played(lm.media_info.media.rowid);
				sideTree.updateAlreadyPlayed();

#if HAVE_ZEITGEIST
				var event = new Zeitgeist.Event.full(Zeitgeist.ZG_ACCESS_EVENT,
					Zeitgeist.ZG_SCHEDULED_ACTIVITY, "app://beatbox.desktop",
					new Zeitgeist.Subject.full(
					lm.media_info.media.uri,
					Zeitgeist.NFO_AUDIO, Zeitgeist.NFO_FILE_DATA_OBJECT,
					"text/plain", "", lm.media_info.media.title, ""));
				new Zeitgeist.Log ().insert_events_no_reply(event);
#endif
			}

			// at halfway, scrobble
			if((double)(sec/(double)lm.media_info.media.length) > 0.50 && !scrobbled_track) {
				scrobbled_track = true;
				try {
					Thread.create<void*>(lastfm_scrobble_thread_function, false);
				}
				catch(GLib.ThreadError err) {
					warning("ERROR: Could not create last fm thread: %s \n", err.message);
				}
			}

			// at 90% done with media, add 1 to play count
			if((double)(sec/(double)lm.media_info.media.length) > 0.90 && !added_to_play_count) {
				added_to_play_count = true;
				lm.media_info.media.play_count++;
				lm.update_media(lm.media_info.media, false, false);
			}

		}
		else {

		}
	}

	public void media_not_found(int id) {
		var not_found = new FileNotFoundDialog(lm, this, id);
		not_found.show();
	}

	public virtual void similarRetrieved(LinkedList<int> similarIDs, LinkedList<Media> similarDont) {
		Widget w = sideTree.getWidget(sideTree.playlists_similar_iter);

		((ViewWrapper)w).similarsFetched = true;
		((ViewWrapper)w).doUpdate(((ViewWrapper)w).currentView, similarIDs, true, true, false);

		infoPanel.updateMediaList(similarDont);

		if(((ViewWrapper)w).isCurrentView && !((ViewWrapper)w).list.get_is_current()) {
			miller.populateColumns("", ((ViewWrapper)w).list.get_medias());
			updateMillerColumns();
		}
	}

	public void set_statusbar_info (ViewWrapper.Hint media_type, uint total_medias,
									 uint total_mbs, uint total_seconds)
	{
		statusBar.set_total_medias (total_medias, media_type);
		statusBar.set_files_size (total_mbs);
		statusBar.set_total_time (total_seconds);
	}

	public void welcomeScreenActivated(int index) {
		if(index == 0) {
			if(!lm.doing_file_operations()) {
				string folder = "";
				var file_chooser = new FileChooserDialog (_("Choose Music Folder"), this,
										  FileChooserAction.SELECT_FOLDER,
										  Gtk.Stock.CANCEL, ResponseType.CANCEL,
										  Gtk.Stock.OPEN, ResponseType.ACCEPT);
				file_chooser.set_local_only(true);
				if (file_chooser.run () == ResponseType.ACCEPT) {
					folder = file_chooser.get_filename();
				}
				file_chooser.destroy ();

				if(folder != "" && (folder != settings.getMusicFolder() || lm.media_count() == 0)) {
					setMusicFolder(folder);
				}
			}
		}
		else {
			if(lm.doing_file_operations())
				return;

			Device d = welcome_screen_keys.get(index);

			if(d.getContentType() == "cdrom") {
				sideTree.expandItem(sideTree.convertToFilter(sideTree.devices_iter), true);
				sideTree.setSelectedIter(sideTree.convertToFilter(sideTree.devices_cdrom_iter));
				sideTree.sideListSelectionChange();

				var to_transfer = new LinkedList<int>();
				foreach(int i in d.get_medias())
					to_transfer.add(i);

				d.transfer_to_library(to_transfer);
			}
			else {
				// ask the user if they want to import medias from device that they don't have in their library (if any)
				if(lm.settings.getMusicFolder() != "") {
					var externals = new LinkedList<int>();
					foreach(var i in d.get_medias()) {
						if(lm.media_from_id(i).isTemporary)
							externals.add(i);
					}

					TransferFromDeviceDialog tfdd = new TransferFromDeviceDialog(this, d, externals);
					tfdd.show();
				}
			}
		}
	}

	public virtual void infoPanelResized(Allocation rectangle) {
		int height, width;
		get_size(out width, out height);

		if(sourcesToMedias.get_position() > height/2)
			return;

		if(mediasToInfo.get_position() < (lm.settings.getWindowWidth() - lm.settings.getSidebarWidth()) - 300) { // this is max size
			mediasToInfo.set_position((lm.settings.getWindowWidth() - lm.settings.getSidebarWidth()) - 300);
			return;
		}
		else if(mediasToInfo.get_position() > (lm.settings.getWindowWidth() - lm.settings.getSidebarWidth()) - 150) { // this is min size
			mediasToInfo.set_position((lm.settings.getWindowWidth() - lm.settings.getSidebarWidth()) - 150);
			return;
		}

		if(lm.settings.getMoreWidth() != rectangle.width) {
			lm.settings.setMoreWidth(rectangle.width);
		}
	}

	public virtual void repeatChooserOptionChanged(int val) {
		lm.settings.setRepeatMode(val);

		if(val == 0)
			lm.repeat = LibraryManager.Repeat.OFF;
		else if(val == 1)
			lm.repeat = LibraryManager.Repeat.MEDIA;
		else if(val == 2)
			lm.repeat = LibraryManager.Repeat.ALBUM;
		else if(val == 3)
			lm.repeat = LibraryManager.Repeat.ARTIST;
		else if(val == 4)
			lm.repeat = LibraryManager.Repeat.ALL;
	}

	public virtual void shuffleChooserOptionChanged(int val) {
		if(val == 0)
			lm.setShuffleMode(LibraryManager.Shuffle.OFF, true);
		else if(val == 1)
			lm.setShuffleMode(LibraryManager.Shuffle.ALL, true);
	}

	public virtual bool addPlaylistChooserOptionClicked() {
		sideTree.playlistMenuNewClicked();
		return true;
	}

	public virtual void infoPanelChooserOptionChanged(int val) {
		infoPanel.set_visible(val == 1);
		lm.settings.setMoreVisible(val == 1);
	}

	public void updateMillerColumns() {
		if(viewSelector.selected != 3)
			settings.setViewMode(viewSelector.selected);

		bool similarcheck = sideTree.getSelectedWidget() is ViewWrapper  &&
							((ViewWrapper)sideTree.getSelectedWidget()).errorBox != null &&
							((ViewWrapper)sideTree.getSelectedWidget()).errorBox.visible;
		bool isCdrom = sideTree.getSelectedObject() is Device && ((Device)sideTree.getSelectedObject()).getContentType() == "cdrom";
		bool isDeviceView = sideTree.getSelectedWidget() is DeviceView/* && ((DeviceView)sideTree.getSelectedWidget()).currentViewIndex() == 0*/;
		bool storecheck = (sideTree.getSelectedWidget() is Store.StoreView);
		bool haveMedias = (lm.media_count() != 0);

		miller.set_visible(viewSelector.selected == 2 && !similarcheck && !storecheck && !isCdrom && !isDeviceView && haveMedias);
		millerVisible = (viewSelector.selected == 0); // used for when an album is clicked from icon view

		// populate if selected == 2 (miller columns)
		/*if(initializationFinished && viewSelector.selected == 2 && sideTree.getSelectedWidget() is ViewWrapper && miller.visible) {
			ViewWrapper vw = (ViewWrapper)sideTree.getSelectedWidget();

			miller.populateColumns("", vw.medias);
		}*/
	}

	// create a thread to update ALL non-visible views
	void searchFieldChanged() {
		/*if(initializationFinished && searchField.get_text().length != 1) {
			try {
				Thread.create<void*>(lm.update_views_thread, false);
			}
			catch(GLib.ThreadError err) {

			}
		}*/
	}
	void millerChanged() {
		/*if(initializationFinished) {
			// start thread to prepare for when it is current
			try {
				Thread.create<void*>(lm.update_views_thread, false);
			}
			catch(GLib.ThreadError err) {

			}
		}*/
	}

	public void searchFieldActivate() {
		Widget w = sideTree.getSelectedWidget();

		if(w is ViewWrapper) {
			ViewWrapper vw = (ViewWrapper)w;

			vw.list.set_as_current_list(1, !vw.list.get_is_current());
			lm.current_index = 0;
			lm.playMedia(lm.mediaFromCurrentIndex(0), false);

			if(!lm.playing)
				playClicked();
		}
	}

	public virtual void dragReceived(Gdk.DragContext context, int x, int y, Gtk.SelectionData data, uint info, uint timestamp) {
		if(dragging_from_music)
			return;

		var files_dragged = new LinkedList<string>();
		debug("dragged\n");
		foreach (string uri in data.get_uris ()) {
			files_dragged.add(File.new_for_uri(uri).get_path());
		}

		lm.add_files_to_library(files_dragged);
	}

	public void doAlert(string title, string message) {
		var dialog = new MessageDialog(this, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK,
				title);

		dialog.title = "BeatBox";
		dialog.secondary_text = message;
		dialog.secondary_use_markup = true;

		dialog.run();
		dialog.destroy();
	}

	/* device stuff for welcome screen */
	public void device_added(Device d) {
		// add option to import in welcome screen
		string secondary = (d.getContentType() == "cdrom") ? _("Import songs from audio CD") : _("Import media from device");
		int key = welcomeScreen.append_with_image( new Image.from_gicon(d.get_icon(), Gtk.IconSize.DIALOG), d.getDisplayName(), secondary);
		welcome_screen_keys.set(key, d);
	}

	public void device_removed(Device d) {
		// remove option to import from welcome screen
		int key = 0;
		foreach(int i in welcome_screen_keys.keys) {
			if(welcome_screen_keys.get(i) == d) {
				key = i;
				break;
			}
		}

		if(key != 0) {
			welcome_screen_keys.unset(key);
			welcomeScreen.remove_with_key(key);
		}
	}
}
