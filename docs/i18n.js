// Dua bahasa untuk halaman ini. Teks Indonesia ada langsung di index.html; teks Inggris ada di
// sini dengan kunci yang sama dengan atribut data-t (isi elemen) dan data-ta (aria-label).
// Teks yang dibuat app.js memakai L('indonesia', 'english'), sama seperti di app.
window.I18N = (() => {
  const EN = {
    'nav.features': 'Features',
    'nav.how': 'How to use',
    'nav.data': 'Data',
    'nav.faq': 'FAQ',
    'nav.get': 'Download',
    'lang.btn': 'ID',
    'lang.aria': 'Ganti ke Bahasa Indonesia',
    'notch.aria': 'Cognify Notch preview',

    // Isi contoh di dalam notch
    's.songline': 'Long Way Home · Porch Light',
    's.ev1': '<b>Morning assembly</b><small>07:00 · School</small>',
    's.ev2': '<b>Online physics class</b><small>10:00 · in 5 min</small>',
    's.ev3': '<b>Biology quiz</b><small>Tomorrow 08:00</small>',
    's.join': 'Join',
    's.quick': 'Quick note',
    's.calc': '= 3,750,000',
    's.calcHint': 'Press Enter to save the result',
    's.noteHint': 'Enter saves to Notes',
    's.song': '<b>Long Way Home</b><small>Porch Light</small>',
    's.play': 'Play or pause',
    's.focus': 'Focus',
    's.length': 'Length',
    's.custom': 'Custom',
    's.reset': 'Reset',
    's.today': 'Today',
    's.sessions': '2 of 4 sessions',
    's.pause': 'Pause',
    's.countdown': 'Countdown',
    's.min20': '20 min',
    's.min10': '10 min',
    's.start': 'Start',
    's.drink': 'Drink 250 ml',
    's.remind': 'Every 60 min, 8:00-21:00',
    's.todoPh': 'New task, e.g. call at 5pm',
    's.markDone': 'Mark as done',
    's.markUndone': 'Mark as not done',
    's.todo1': 'Do math homework',
    's.todo2': 'Reply to the group chat',
    's.doneLabel': 'done',
    's.todo3': 'Bring lab coat',
    's.todo3due': 'Tomorrow 07:00',
    's.note1': 'Hand in biology homework tomorrow at 10',
    's.ago1': '2 min ago',
    's.note2': 'Presentation idea: start with an everyday example',
    's.ago2': 'this morning',
    's.note3': 'Circle area: A = π × r²',
    's.ago3': 'yesterday',
    's.search': 'Search',
    's.pin': 'Pin',
    's.clip2': 'Chapter 4, page 88, questions 1 to 10',
    's.clip3': 'Image · 1280 × 720',
    's.file1': '<i data-lucide="file-text"></i><b>biology-report.pdf</b><small>2.4 MB</small>',
    's.file2': '<i data-lucide="image"></i><b>group-photo.jpg</b><small>3.1 MB</small>',
    's.file3': '<i data-lucide="folder"></i><b>Physics Homework</b><small>Folder</small>',
    's.drop': '<i data-lucide="plus"></i><b>Drop files here</b><small>and drag them out anytime</small>',
    's.mirror': 'Front camera preview. Nothing is recorded.',
    's.sc1': 'Study mode',
    's.sc2': 'Silence notifications',
    's.sc3': 'Open Classroom',
    's.sc4': 'Log study time',
    's.sc5': 'Play lo-fi',
    's.pages': 'Pages',

    // Pembuka
    'hero.title': 'The notch on your screen,<br><span class="hl">finally useful.</span>',
    'hero.lead': 'Songs, lyrics, your agenda, study timers, notes, and files appear in the notch when your cursor comes near, then disappear when it moves away.',
    'get.mac': 'Download for Mac',
    'get.win': 'Download for Windows (Beta)',
    'os.label': 'Preview for',
    'get.source': 'Source code',
    'get.latest': 'Latest version',
    'hero.meta': 'Free · macOS 13 or later · Windows 11 (Beta)',
    'd.menu': '<b>Notes</b><span>File</span><span>Edit</span><span>View</span>',
    'd.notes': 'Notes',
    'd.noteTitle': 'Photosynthesis',
    'd.cal': 'Calendar',
    'd.ev1': '<b>Assembly</b><small>07:00</small>',
    'd.ev2': '<b>Physics class</b><small>10:00</small>',
    'd.ev3': '<b>Guitar lesson</b><small>16:00</small>',
    'hero.tryHover': 'Point at the notch on this screen to try it.',
    'hero.tryTouch': 'Tap the notch on this screen to try it.',

    // Fitur
    'f.title': 'Eleven pages.<br>One notch.',
    'f.lead': 'Scroll slowly. The notch at the top changes to match the feature you are reading about. Everything in it is sample content, not your data.',
    'f.music': '<span class="tag"><i data-lucide="music"></i>Music</span><h3>Music from any app.</h3><p>Spotify, Apple Music, YouTube in your browser, VLC, and more. The album art sits on the left, and the equalizer on the right moves with the sound: low notes on the left, high notes on the right. On Windows, the equalizer follows the loudness.</p>',
    'h.music': '<b>How to use</b><ol><li>Play music as usual.</li><li>Point at the notch.</li><li>Play, pause, skip, shuffle, repeat, set the volume, or pick speakers and AirPods.</li></ol>',
    'f.title2': '<span class="tag"><i data-lucide="text"></i>Song title</span><h3>New song, quick title.</h3><p>When the song changes, the left side of the notch widens to show its title. Long titles scroll once, then the notch returns to its usual size.</p>',
    'h.title2': '<b>How to use</b><ol><li>Works automatically, nothing to set up.</li><li>You can turn it off in Settings.</li></ol>',
    'f.lyrics': '<span class="tag"><i data-lucide="mic-vocal"></i>Lyrics</span><h3>Sing along, line by line.</h3><p>The Music page shows lyrics that light up with the song. Click a line to jump to that part.</p>',
    'h.lyrics': '<b>How to use</b><ol><li>Open the notch.</li><li>Swipe with two fingers to the Music page.</li><li>Lyrics come from LRCLIB, a free lyrics library built by its community.</li></ol>',
    'f.wing': '<span class="tag"><i data-lucide="captions"></i>Lyrics beside the notch</span><h3>Without opening anything.</h3><p>The line being sung runs along the right side of the notch, so you can keep working.</p>',
    'h.wing': '<b>How to use</b><ol><li>Open Settings.</li><li>Turn on Lyrics in the closed notch.</li></ol>',
    'f.agenda': '<span class="tag"><i data-lucide="calendar"></i>Agenda</span><h3>Today and tomorrow at a glance.</h3><p>Events come from the Calendar app. Zoom, Google Meet, Teams, and Webex meetings get a Join button.</p>',
    'h.agenda': '<b>How to use</b><ol><li>Open the notch. Your agenda is on the Home page.</li><li>Allow Calendar access when asked.</li></ol>',
    'f.meeting': '<span class="tag"><i data-lucide="video"></i>Meetings</span><h3>Never late for an online class.</h3><p>Five minutes before a meeting starts, the notch opens on its own with a Join button. One click and you are in.</p>',
    'h.meeting': '<b>How to use</b><ol><li>Works automatically for Calendar events that have a meeting link.</li></ol>',
    'f.note': '<span class="tag"><i data-lucide="pencil-line"></i>Quick note</span><h3>Type, speak, or calculate.</h3><p>Write one line and press Enter to save it. On Mac, the microphone button turns speech into text right on this Mac. Type <em>1250000 * 3</em>, <em>15% of 200</em>, or <em>5 km to miles</em> and the answer appears instantly.</p>',
    'h.note': '<b>How to use</b><ol><li>Open the notch and start typing.</li><li>Or press <span class="kbd">⌃⌥N</span> from any app.</li></ol>',
    'f.pomo': '<span class="tag"><i data-lucide="timer"></i>Pomodoro</span><h3>Focus first, break later.</h3><p>Choose 25/5, 50/10, 90/15, or set your own lengths. The time left shows beside the notch, and the notch tells you when it is time for a break.</p>',
    'h.pomo': '<b>How to use</b><ol><li>Open the Pomodoro page.</li><li>Pick a length, then click Start.</li></ol>',
    'f.clock': '<span class="tag"><i data-lucide="alarm-clock"></i>Stopwatch and timers</span><h3>From instant noodles to a morning run.</h3><p>A stopwatch with laps, plus several countdowns at once. Countdowns keep running while the notch is closed.</p>',
    'h.clock': '<b>How to use</b><ol><li>Open the Stopwatch &amp; Timer page.</li><li>Pick 1 to 30 minutes, or set your own length.</li></ol>',
    'f.water': '<span class="tag"><i data-lucide="droplet"></i>Water</span><h3>Two liters, a glass at a time.</h3><p>Set a daily goal and a glass size. The notch reminds you during your active hours and shows an hourly chart of what you drank.</p>',
    'h.water': '<b>How to use</b><ol><li>Click Drink each time you drink.</li><li>Set the goal, active hours, and reminder interval from the settings icon.</li></ol>',
    'f.todo': '<span class="tag"><i data-lucide="list-checks"></i>To-do list</span><h3>Write it the way you say it.</h3><p>For example "call mom at 5pm" or "bring lab coat tomorrow at 7". The time is picked up automatically, and the notch reminds you when it comes.</p>',
    'h.todo': '<b>How to use</b><ol><li>Type a task on the To-do page.</li><li>Turn on sync with Reminders if you want your tasks on your iPhone too.</li></ol>',
    'f.clip': '<span class="tag"><i data-lucide="clipboard-list"></i>Clipboard</span><h3>What you copied is still here.</h3><p>Your recent text, links, and images. Pin the ones you use often, or search by keyword. Anything copied from a password manager is not kept.</p>',
    'h.clip': '<b>How to use</b><ol><li>Open the Clipboard page.</li><li>Click a row to copy it again.</li></ol>',
    'f.tray': '<span class="tag"><i data-lucide="inbox"></i>Tray</span><h3>A parking spot for files.</h3><p>Drop files on the notch, then drag them out to a chat, an email, or another folder. Files stay where they are, so they take up no extra space.</p>',
    'h.tray': '<b>How to use</b><ol><li>Drag files onto the notch.</li><li>Drag them out, send them with AirDrop, or rename them.</li></ol>',
    'f.mirror': '<span class="tag"><i data-lucide="scan-face"></i>Mirror</span><h3>Fix your hair before the camera turns on.</h3><p>The camera is only on while the Mirror page is open, and nothing is recorded.</p>',
    'h.mirror': '<b>How to use</b><ol><li>Open the Mirror page.</li></ol>',
    'f.shortcuts': '<span class="tag"><i data-lucide="zap"></i>Shortcuts</span><h3>One click, one routine.</h3><p>Run your favorite Siri Shortcuts, such as study mode, silencing notifications, or opening your class website.</p>',
    'h.shortcuts': '<b>How to use</b><ol><li>Open the Shortcuts page.</li><li>The list comes from the Shortcuts app.</li></ol>',
    'f.cards': '<span class="tag"><i data-lucide="bell"></i>Quick updates</span><h3>Your computer speaks up a little.</h3><p>Charger plugged in, AirPods or headphones connected, a download finished or failed, Caps Lock on, keyboard language changed, or the internet dropped. The notch tells you briefly, then goes quiet.</p>',
    'h.cards': '<b>How to use</b><ol><li>Works automatically.</li><li>Each kind of update can be turned off from the notch icon in the menu bar.</li></ol>',
    'f.hud': '<span class="tag"><i data-lucide="sun"></i>Volume and brightness</span><h3>Volume and brightness, in the notch.</h3><p>When you change the volume or brightness, the level shows neatly beside the notch.</p>',
    'h.hud': '<b>How to use</b><ol><li>Press the volume or brightness keys as usual.</li></ol>',
    'f.idle': '<span class="tag"><i data-lucide="eye"></i>A little friend</span><h3>Company when it is quiet.</h3><p>A pair of small eyes appears while the notch is idle, and they get sleepy if you are away for a while. The notch also steps aside when you watch something in full screen.</p>',
    'h.idle': '<b>How to use</b><ol><li>Works automatically.</li><li>Both can be turned off in Settings.</li></ol>',

    // Gerakan
    'g.title': 'Eight gestures,<br>easy to remember.',
    'g.1': '<b>Point at the notch</b><p>The panel opens. Move the cursor away to close it.</p>',
    'g.2': '<b>Swipe with two fingers</b><p>One swipe moves one page. On the Music page, swipe to change songs.</p>',
    'g.3': '<b>Dots under the panel</b><p>Point at the dots and they grow into icons, like the Dock. Click one to jump straight there.</p>',
    'g.4': '<b>Open from the keyboard</b><p>Start typing right away. The arrow keys or 1 to 9 switch pages, and Esc closes the panel.</p>',
    'g.5': '<b>Drag a file onto the notch</b><p>It goes into the Tray.</p>',
    'g.6': '<b>Open with a click</b><p>Prefer clicking to pointing? Turn it on in Settings.</p>',
    'g.7': '<b>Menu bar or tray icon</b><p>Turn each feature on or off, check for updates, and quit the app. On Windows, features are set with the gear icon in the notch.</p>',
    'g.8': '<b>Settings</b><p>Panel size, delays before the panel opens and closes, page order, screen, weather city, language, and data export and import. Settings are more compact on Windows.</p>',

    // Data
    'd2.title': 'Your data stays<br>on your computer.',
    'd2.lead': 'No account, no analytics, and nothing is sent to the developer. Only three features use the internet, and all of them are listed below.',
    'd2.net': 'What uses the internet',
    'd2.lyrics': 'Lyrics',
    'd2.lyricsDl': '<dt>Sends</dt><dd>Song title, artist, album, and length</dd><dt>To</dt><dd><a href="https://lrclib.net">LRCLIB</a> (lrclib.net)</dd><dt>Default</dt><dd>On, can be turned off</dd>',
    'd2.weather': 'Weather',
    'd2.weatherDl': '<dt>Sends</dt><dd>The city you choose and its coordinates</dd><dt>To</dt><dd><a href="https://open-meteo.com">Open-Meteo</a> (open-meteo.com)</dd><dt>Default</dt><dd>Off</dd>',
    'd2.updateDl': '<dt>Sends</dt><dd>Nothing about your computer. The app only fetches the list of versions.</dd><dt>To</dt><dd>GitHub</dd><dt>Default</dt><dd>On. On Mac, automatic install can be turned off. On Windows it is automatic too, and can be turned off in Settings.</dd>',
    'd2.winNote': 'On Windows, the agenda from an ICS calendar also fetches the link you enter yourself. It is off by default, and without a link nothing is requested at all.',
    'd2.local': 'What never leaves your computer',
    'd2.l1': '<b>Calendar</b>Read only to show today\'s and tomorrow\'s agenda.',
    'd2.l2': '<b>Clipboard</b>The last 40 text items. Images are kept only while the app runs. Password manager content is skipped.',
    'd2.l3': '<b>Notes, to-dos, water, and timers</b>Stored on this computer. On Mac, you can export and import them yourself.',
    'd2.l4': '<b>Reminders (Mac)</b>Only when sync is on. Syncing to your iPhone is handled by the Reminders app and your iCloud.',
    'd2.l5': '<b>Microphone (Mac)</b>Speech is turned into text on this Mac. Only the text is kept.',
    'd2.l6': '<b>Camera</b>Only for Mirror, and never recorded.',
    'd2.l7': '<b>Audio being played</b>Only turned into equalizer bar heights in memory.',
    'd2.l8': '<b>Files in the tray</b>The notch only keeps their location. Files stay where they are.',
    'd2.l9': '<b>Downloads</b>Progress is read from your Downloads folder and not stored.',
    'd2.perms': 'Permissions it asks for',
    'd2.permsNote': 'Each permission is requested the first time you use the feature. If you decline, only that feature stops working. This list is for macOS. Windows only asks for camera access, for Mirror.',
    'd2.p1': '<b>Calendar</b>for the agenda',
    'd2.p2': '<b>Reminders</b>for to-do sync',
    'd2.p3': '<b>Camera</b>for Mirror',
    'd2.p4': '<b>Microphone and Speech Recognition</b>for voice notes',
    'd2.p5': '<b>Audio from other apps</b>for the equalizer',

    // Spesifikasi
    'sp.size': 'download size on Mac, 12 MB on Windows',
    'sp.os': 'macOS Ventura or later, or Windows 11 (Beta)',
    'sp.acc': 'accounts to create',
    'sp.lang': 'languages: Indonesian and English',
    'sp.cpu': '<b>Processor</b>Apple Silicon and Intel on Mac. 64-bit Windows 11.',
    'sp.nonotch': '<b>Screens without a notch</b>Still works: the notch appears as a small panel at the top center of the screen. Windows has no physical notch, so there it always appears that way, on the main display. On Mac, external displays can be chosen in Settings.',
    'sp.sec': '<b>Security</b>Mac: signed and notarized by Apple, so the app opens without warnings. Windows: not signed yet, so a SmartScreen warning appears.',
    'sp.upd': '<b>Updates</b>Mac: automatic through Sparkle, installed while the notch is not in use. Windows: automatic too, installed while the notch is not in use.',
    'sp.win': '<b>Windows (Beta)</b>Only tested on one Windows 11 laptop so far. Dragging files to the Tray and voice notes are not available on Windows yet.',
    'sp.lic': '<b>License</b>AGPL-3.0. The source code is open on GitHub.',

    // Tanya jawab
    'q.title': 'Questions and answers',
    'q.1': '<summary>Is Cognify Notch free?</summary><p>Yes. Cognify Notch is free, open source, with no account and no ads.</p>',
    'q.2': '<summary>My screen has no notch. Can I still use it?</summary><p>Yes. On Macs without a notch, on external displays, and on Windows, the notch appears as a small panel at the top center of the screen. On Mac, you can choose the screen in Settings.</p>',
    'q.3': '<summary>Why does the song I am playing not show up?</summary><p>Since macOS 15.4, Apple only lets its own programs read what is playing. Cognify Notch uses the same method as Boring Notch to keep reading it. If Apple closes that path, the music section is hidden and every other feature keeps working. On Windows, songs are read from the Windows media controls, so Spotify, browsers, and other players that show up there are picked up too.</p>',
    'q.4': '<summary>Why does a song have no lyrics?</summary><p>Lyrics come from LRCLIB, a free lyrics library built by its community. Popular songs are almost always there, but some local or new songs may not be yet.</p>',
    'q.5': '<summary>How do updates work?</summary><p>Automatically. New versions download in the background and install while the notch is not in use, and the app restarts in about a second. If you are several versions behind, it goes straight to the latest one. To turn this off, click the notch icon in the menu bar and turn off Install updates automatically. On Windows it is automatic too: the app checks once a day, downloads in the background, and installs while the notch is not in use. Automatic updates can be turned off in Settings.</p>',
    'q.6': '<summary>Will it slow down my computer or drain the battery?</summary><p>It shouldn\'t. When idle, the notch only checks the cursor position when it needs to, so it uses almost no CPU. While music plays, the equalizer and lyrics add a little. On Windows, the eyes can be hidden in Settings, and the "follow the cursor" option uses slightly more power than plain blinking.</p>',
    'q.9': '<summary>Is there a Windows version?</summary><p>Yes, still in Beta. Cognify Notch for Windows 11 has most of the Mac version\'s features, except dragging files to the Tray and voice notes. Once installed, the app updates itself.</p>',
    'q.10': '<summary>Why does Windows show a SmartScreen warning?</summary><p>The Windows installer is not signed with a paid certificate yet, so Windows warns about apps it does not know. Click More info, then Run anyway. The code is open on GitHub, so you can inspect it or build it yourself.</p>',
    'q.7': '<summary>How do I stop or remove it?</summary><p>Click the notch icon in the menu bar. Turn off Open at login so the app does not start on its own, or choose Quit. To remove it, drag Cognify Notch from the Applications folder to the Trash. On Windows, right-click the notch icon in the tray and choose Quit, then remove it in Windows Settings, Apps.</p>',
    'q.8': '<summary>Does Cognify Notch collect data?</summary><p>No. There is no account and no analytics. The <a href="#data">Data</a> section above and the <a href="privasi.html">privacy policy</a> list every feature that uses the internet.</p>',

    // Unduh
    'get.title': 'Try it now.',
    'get.steps': 'Mac: open the DMG file, drag the app to your Applications folder, then point at the notch. Windows: run the Setup file, then point at the top of the screen.',
    'get.os': 'macOS 13 or later · Windows 11 (Beta)',
    'get.new': 'What\'s new on Mac',
    'get.newNote': 'Release notes are written in Indonesian.',
    'get.all': 'All release notes',
    'd2.policy': 'The full details are in the <a href="privasi.html">privacy policy</a>, and the usage rules in the <a href="syarat.html">terms of use</a>.',
    'foot.priv': 'Privacy policy',
    'foot.terms': 'Terms of use',
    'q.11': '<summary>On Windows, how do I hide the notch or make it narrower?</summary><p>Left-click the Cognify Notch icon in the taskbar\'s hidden icons (the small arrow) to hide or show the notch. Right-click opens a menu: Hide or Show notch, Settings, and Quit. In Settings, the "Closed notch width" slider narrows the pill so it does not cover browser tabs. The open panel does not change.</p>',
    'q.12': '<summary>Can the two dots (eyes) on the notch be turned off?</summary><p>Yes, and notices like charger, volume, and downloads still appear. Windows Settings has a "Show the eyes" switch and an eye movement choice: Blink (default) or Follow cursor. On Mac, turn off "Eyes when idle" in Settings.</p>',
    'sp.winx': '<b>Windows only</b>Settings live in their own window (the gear button on the notch or the tray icon menu). There is a closed notch width slider, switches and movement for the eyes, and hide or show the notch from the tray icon. Notices, the volume and brightness HUD, and Pomodoro are laid out like the Mac version.',
    'w.tag': 'Work in progress',
    'w.title': 'Cognify,<br>the main notes space.',
    'w.lead': 'A desktop app for documents, boards, and a calendar in one place, for students and everyone else. Free, no account, and your data stays on your computer. Not available to download yet.',
    'w.l1': '<b>Documents and boards</b>Nested pages, fast search, and a drawing board.',
    'w.l2': '<b>Calendar</b>Events, repeats, reminders, and ICS subscriptions.',
    'w.l3': '<b>Connects to Cognify Notch</b>One button shows your Notch data in Cognify. Optional.',
    'w.note': 'Features and looks may still change. Tables, a Windows version, and a few other things are not finished.',
    'foot': 'The notch content on this page is sample content. Mac and MacBook are trademarks of Apple Inc. Windows is a trademark of Microsoft Corporation.',
  };

  const META = {
    id: {
      title: 'Cognify Notch: notch dengan isi untuk Mac dan Windows',
      description: 'Notch untuk Mac dan Windows: lagu, lirik tersinkron, agenda, timer belajar, catatan, clipboard, dan file di satu panel. Gratis, open source, tanpa akun.',
    },
    en: {
      title: 'Cognify Notch: a notch with something in it, for Mac and Windows',
      description: 'A notch for Mac and Windows: music, synced lyrics, agenda, study timers, notes, clipboard, and files in one panel. Free, open source, no account.',
    },
  };

  // Teks Indonesia diambil dari halaman sekali, sebelum bahasa pertama kali diganti.
  const original = new Map();
  const originalAria = new Map();
  document.querySelectorAll('[data-t]').forEach((el) => original.set(el, el.innerHTML));
  document.querySelectorAll('[data-ta]').forEach((el) => originalAria.set(el, el.getAttribute('aria-label')));

  let lang = document.documentElement.lang === 'en' ? 'en' : 'id';
  const listeners = [];

  function render() {
    original.forEach((html, el) => {
      const en = EN[el.dataset.t];
      el.innerHTML = lang === 'en' && en !== undefined ? en : html;
    });
    originalAria.forEach((text, el) => {
      const en = EN[el.dataset.ta];
      el.setAttribute('aria-label', lang === 'en' && en !== undefined ? en : text);
    });
    document.documentElement.lang = lang;
    document.querySelector('meta[name="description"]').content = META[lang].description;
    document.title = META[lang].title;
  }

  function set(next) {
    lang = next === 'en' ? 'en' : 'id';
    try { localStorage.setItem('lang', lang); } catch (e) { /* tetap jalan tanpa penyimpanan */ }
    const url = new URL(location.href);
    if (url.searchParams.has('lang')) { url.searchParams.set('lang', lang); history.replaceState(null, '', url); }
    const swap = () => { render(); listeners.forEach((fn) => fn(lang)); };
    // Dengan animasi, teks memudar dulu, lalu muncul lagi dalam bahasa baru.
    if (!document.documentElement.classList.contains('motion')) { swap(); return; }
    document.body.classList.add('swapping');
    setTimeout(() => {
      swap();
      requestAnimationFrame(() => document.body.classList.remove('swapping'));
    }, 170);
  }

  render();
  return {
    get lang() { return lang; },
    L: (id, en) => (lang === 'en' ? en : id),
    set,
    toggle: () => set(lang === 'en' ? 'id' : 'en'),
    onChange: (fn) => listeners.push(fn),
  };
})();
