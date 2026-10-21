// Pratinjau notch di halaman. Satu elemen notch mula-mula duduk di layar laptop pada bagian
// pembuka, lalu naik dan menempel di tepi atas jendela (di antara dua pil navigasi) saat digulir.
// Isinya mengikuti bagian yang sedang dibaca, dan bisa dicoba dengan hover, geser dua jari,
// titik halaman, dan keyboard. Warna latar halaman mengikuti data-bg bagian yang sedang dibaca.
// Semua isi adalah contoh.
(() => {
  const N = document.getElementById('notch');
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const icons = () => window.lucide && window.lucide.createIcons();

  const TABS = [
    ['home', 'house', 'Beranda'],
    ['music', 'music', 'Musik'],
    ['timer', 'timer', 'Pomodoro'],
    ['clock', 'alarm-clock', 'Stopwatch & Timer'],
    ['water', 'droplet', 'Pengingat Minum'],
    ['todo', 'list-checks', 'Daftar Tugas'],
    ['notes', 'notebook-pen', 'Catatan'],
    ['clipboard', 'clipboard-list', 'Clipboard'],
    ['tray', 'inbox', 'Tray'],
    ['mirror', 'scan-face', 'Cermin'],
    ['shortcuts', 'zap', 'Pintasan'],
  ];
  // lebar, tinggi, radius sudut bawah
  const SIZES = {
    idle: [190, 36, 12], music: [300, 36, 12], title: [470, 36, 12], lyric: [520, 36, 12],
    hud: [300, 36, 12], card: [400, 84, 22], open: [680, 256, 30],
  };

  let current = '';
  let scrollState = 'demo';
  let docked = false;
  const display = $('#display');
  let hovering = false;
  let page = 'home';
  let leaveTimer = 0;

  // ---------- Titik halaman ----------
  const dots = $('#dots');
  TABS.forEach(([id, icon, title]) => {
    const b = document.createElement('button');
    b.dataset.tab = id;
    b.setAttribute('aria-label', title);
    b.innerHTML = `<i data-lucide="${icon}"></i>`;
    b.addEventListener('click', () => setPage(id));
    dots.appendChild(b);
  });
  const tip = document.createElement('span');
  tip.className = 'tip';
  dots.appendChild(tip);

  // Efek Dock: makin dekat ke kursor, makin besar.
  dots.addEventListener('pointermove', (e) => {
    dots.classList.add('hover');
    let nearest = null, best = Infinity;
    $$('button', dots).forEach((b) => {
      const r = b.getBoundingClientRect();
      const d = Math.abs(e.clientX - (r.left + r.width / 2)) / scale();
      const z = Math.cos(Math.min(d / 80, 1) * Math.PI / 2);
      b.style.setProperty('--z', (0.55 + 0.45 * z).toFixed(3));
      if (d < best) { best = d; nearest = b; }
    });
    if (nearest) {
      tip.textContent = nearest.getAttribute('aria-label');
      const host = dots.getBoundingClientRect();
      const r = nearest.getBoundingClientRect();
      tip.style.left = ((r.left + r.width / 2 - host.left) / scale()) + 'px';
    }
  });
  dots.addEventListener('pointerleave', () => {
    dots.classList.remove('hover');
    $$('button', dots).forEach((b) => b.style.setProperty('--z', 0));
  });

  function scale() { return parseFloat(N.style.getPropertyValue('--s')) || 1; }

  // ---------- Halaman di panel ----------
  function setPage(id, dir) {
    const order = TABS.map((t) => t[0]);
    if (dir === undefined) dir = order.indexOf(id) - order.indexOf(page);
    page = id;
    $$('.page', N).forEach((p) => {
      const on = p.dataset.tab === id;
      p.classList.remove('on', 'from-left');
      if (on) { void p.offsetWidth; p.classList.add('on'); if (dir < 0) p.classList.add('from-left'); }
    });
    $('#pageTitle').textContent = TABS.find((t) => t[0] === id)[2];
    $$('button', dots).forEach((b) => b.classList.toggle('on', b.dataset.tab === id));
  }
  function stepPage(delta) {
    const order = TABS.map((t) => t[0]);
    const i = (order.indexOf(page) + delta + order.length) % order.length;
    setPage(order[i], delta);
  }

  // ---------- Bentuk notch ----------
  function apply(state) {
    if (state === 'demo') state = DEMO[demoIndex % DEMO.length];
    if (state === current) return;
    current = state;
    const [view, arg] = state.split(':');
    const home = $('[data-tab="home"]', N);
    const calc = view === 'open' && arg === 'home-calc';
    home.classList.toggle('home-calc', calc);
    $('#noteText').textContent = calc ? '1.250.000 * 3' : 'Kumpul tugas biologi besok jam 10';
    if (view === 'open') setPage(calc ? 'home' : (arg || page), 0);
    if (view === 'card') startCards(arg); else stopCards();
    if (view === 'hud') animateHud();
    N.dataset.view = view;
    flagNav();
    resize();
  }
  function resize() {
    const [w, h, r] = SIZES[N.dataset.view];
    // Di layar laptop notch mengecil sesuai lebar layar; setelah menempel, ukuran normal.
    const room = docked ? window.innerWidth - 24 : display.clientWidth - 24;
    const s = Math.min(docked ? 1 : display.clientWidth / 1100, room / (w + 20));
    N.style.setProperty('--w', w + 'px');
    N.style.setProperty('--h', h + 'px');
    N.style.setProperty('--r', r + 'px');
    N.style.setProperty('--s', s.toFixed(3));
    // Ruang di atas teks tiap fitur supaya panel terbuka tidak menutupinya.
    const open = Math.min(1, (window.innerWidth - 24) / (SIZES.open[0] + 20));
    document.documentElement.style.setProperty('--step-pad', Math.round(SIZES.open[1] * open + 70) + 'px');
  }

  // Beri tahu navigasi bila notch yang menempel sedang lebar, supaya tautan menu menyingkir.
  function flagNav() {
    const view = N.dataset.view;
    document.body.classList.toggle('notch-wide', docked && ['open', 'lyric', 'title'].includes(view));
    document.body.classList.toggle('notch-busy', docked && view !== 'idle');
  }

  // ---------- Gulir: bagian yang sedang di tengah layar menentukan isi notch ----------
  const steps = $$('[data-notch]');
  const tinted = $$('[data-bg]');
  let bg = '';
  function onScroll() {
    // Menempel di atas begitu tepi atas layar laptop lewat dari tepi atas jendela.
    const top = display.getBoundingClientRect().top;
    const wasDocked = docked;
    docked = top <= 0;
    N.style.setProperty('--top', Math.max(0, top) + 'px');
    if (wasDocked !== docked) {
      resize();
      flagNav();
    }

    const mid = window.innerHeight * 0.55;
    let state = null;
    steps.forEach((el) => {
      const r = el.getBoundingClientRect();
      const active = r.top < mid && r.bottom > mid;
      el.classList.toggle('active', active);
      if (active) state = el.dataset.notch;
    });
    if (!state) state = docked ? 'idle' : 'demo';
    scrollState = state;
    if (!hovering) apply(state);

    let color = '#f4efe6';
    tinted.forEach((el) => {
      const r = el.getBoundingClientRect();
      if (r.top < mid && r.bottom > mid) color = el.dataset.bg;
    });
    if (color !== bg) {
      bg = color;
      document.body.style.backgroundColor = color;
      document.body.classList.toggle('dark', color === '#2a2559');
      document.querySelector('meta[name="theme-color"]').content = color;
    }
  }

  // Di bagian pembuka, notch di layar laptop memperagakan beberapa bentuknya bergantian.
  const DEMO = ['music', 'open:home', 'title', 'open:music', 'card:charging', 'open:water', 'lyric', 'card:airpods'];
  let demoIndex = 0;
  setInterval(() => {
    if (scrollState !== 'demo' || hovering) return;
    demoIndex++;
    apply('demo');
  }, 3200);
  let ticking = false;
  window.addEventListener('scroll', () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => { ticking = false; onScroll(); });
  }, { passive: true });
  window.addEventListener('resize', () => { resize(); onScroll(); });

  // ---------- Hover, ketuk, geser ----------
  function openByUser() {
    hovering = true;
    clearTimeout(leaveTimer);
    if (!current.startsWith('open')) apply('open:' + page);
  }
  function closeByUser(delay) {
    hovering = false;
    clearTimeout(leaveTimer);
    leaveTimer = setTimeout(() => { if (!hovering) apply(scrollState); }, delay);
  }
  N.addEventListener('pointerenter', (e) => { if (e.pointerType !== 'touch') openByUser(); });
  N.addEventListener('pointerleave', (e) => { if (e.pointerType !== 'touch') closeByUser(350); });
  N.addEventListener('click', () => { if (!current.startsWith('open')) openByUser(); });
  document.addEventListener('pointerdown', (e) => {
    if (e.pointerType === 'touch' && hovering && !N.contains(e.target)) closeByUser(0);
  });

  // Geser dua jari: satu geser satu halaman, ada jeda supaya tidak kelewatan.
  let acc = 0, lockUntil = 0;
  N.addEventListener('wheel', (e) => {
    if (N.dataset.view !== 'open' || Math.abs(e.deltaX) <= Math.abs(e.deltaY)) return;
    e.preventDefault();
    if (Date.now() < lockUntil) { acc = 0; return; }
    acc += e.deltaX;
    if (Math.abs(acc) > 40) {
      stepPage(acc > 0 ? 1 : -1);
      acc = 0;
      lockUntil = Date.now() + 450;
    }
  }, { passive: false });
  let touchX = null;
  N.addEventListener('touchstart', (e) => { touchX = e.touches[0].clientX; }, { passive: true });
  N.addEventListener('touchend', (e) => {
    if (touchX === null || N.dataset.view !== 'open') return;
    const dx = e.changedTouches[0].clientX - touchX;
    if (Math.abs(dx) > 40) stepPage(dx < 0 ? 1 : -1);
    touchX = null;
  });
  document.addEventListener('keydown', (e) => {
    if (!hovering || N.dataset.view !== 'open') return;
    if (e.key === 'ArrowRight') stepPage(1);
    else if (e.key === 'ArrowLeft') stepPage(-1);
    else if (e.key === 'Escape') closeByUser(0);
    else if (/^[1-9]$/.test(e.key) && TABS[+e.key - 1]) setPage(TABS[+e.key - 1][0]);
  });

  // ---------- Kartu kabar ----------
  const CARDS = {
    charging: { icon: 'battery-charging', c: '#4cd964', t: 'Mengisi daya', d: 'Charger tersambung · 70%' },
    airpods: { icon: 'headphones', c: '#fff', t: 'AirPods Pro', d: 'Tersambung · L 80%  R 75%' },
    download: { icon: 'download', c: '#4c9bff', t: 'laporan-final.pdf', d: 'Mengunduh', progress: true },
    caps: { icon: 'arrow-big-up', c: '#fff', t: 'Caps Lock', d: 'Nyala' },
    input: { icon: 'keyboard', c: '#fff', t: 'Bahasa keyboard', d: 'ABC' },
    net: { icon: 'wifi-off', c: '#ff9f43', t: 'Internet terputus', d: 'Wi-Fi tidak tersambung' },
    meeting: { icon: 'video', c: '#8f87ff', t: 'Kelas online Fisika', d: 'Mulai 5 menit lagi', end: '<button class="pill accent">Gabung</button>' },
  };
  const CYCLE = ['charging', 'airpods', 'download', 'caps', 'input', 'net'];
  let cardTimer = 0, dlTimer = 0;
  function showCard(key) {
    const c = CARDS[key];
    clearInterval(dlTimer);
    $('#cardIcon').innerHTML = `<i data-lucide="${c.icon}"></i>`;
    $('#cardIcon').style.setProperty('--c', c.c);
    $('#cardTitle').textContent = c.t;
    $('#cardDetail').textContent = c.d;
    $('#cardEnd').innerHTML = c.end || (c.progress ? '<span class="bar"><b style="width:20%"></b></span>' : '');
    icons();
    if (c.progress) {
      let p = 20;
      dlTimer = setInterval(() => {
        p = Math.min(100, p + 9);
        const bar = $('#cardEnd b');
        if (bar) bar.style.width = p + '%';
        $('#cardDetail').textContent = p < 100 ? `Mengunduh · ${p}%` : 'Selesai · 4,2 MB';
        if (p >= 100) clearInterval(dlTimer);
      }, 220);
    }
  }
  function startCards(arg) {
    stopCards();
    if (arg !== 'cycle') { showCard(arg); return; }
    let i = 0;
    showCard(CYCLE[0]);
    cardTimer = setInterval(() => { i = (i + 1) % CYCLE.length; showCard(CYCLE[i]); }, 2800);
  }
  function stopCards() { clearInterval(cardTimer); clearInterval(dlTimer); }

  // ---------- Volume ----------
  let hudTimer = 0;
  function animateHud() {
    clearInterval(hudTimer);
    const levels = [40, 50, 60, 70, 60];
    let i = 0;
    hudTimer = setInterval(() => {
      if (N.dataset.view !== 'hud') return clearInterval(hudTimer);
      $('#hudLevel').style.width = levels[i++ % levels.length] + '%';
    }, 700);
  }

  // ---------- Musik dan lirik ----------
  const lyricBox = $('#lyrics');
  const track = document.createElement('div');
  track.style.transition = 'transform .5s cubic-bezier(.3, .9, .4, 1)';
  track.style.display = 'flex';
  track.style.flexDirection = 'column';
  track.style.gap = '6px';
  $$('p', lyricBox).forEach((p) => track.appendChild(p));
  lyricBox.appendChild(track);
  const lines = $$('p', track);
  let lyricIndex = 0, playing = true, seek = 72;
  function showLyric(i) {
    lyricIndex = (i + lines.length) % lines.length;
    lines.forEach((p, k) => p.classList.toggle('cur', k === lyricIndex));
    track.style.transform = `translateY(${-Math.max(0, lines[lyricIndex].offsetTop - 34)}px)`;
    const wing = $('#wingLyric');
    wing.style.opacity = 0;
    setTimeout(() => { wing.textContent = lines[lyricIndex].textContent; wing.style.opacity = 1; }, 200);
  }
  lines.forEach((p, k) => p.addEventListener('click', () => showLyric(k)));
  setInterval(() => { if (playing) showLyric(lyricIndex + 1); }, 2600);
  $('#playBtn').addEventListener('click', () => {
    playing = !playing;
    N.classList.toggle('paused', !playing);
    $('#playBtn').innerHTML = `<i data-lucide="${playing ? 'pause' : 'play'}"></i>`;
    icons();
  });

  // ---------- Minum ----------
  const water = { 8: 250, 9: 250, 11: 500, 13: 250, 15: 250 };
  function renderWater() {
    const chart = $('#waterChart');
    const total = Object.values(water).reduce((a, b) => a + b, 0);
    const top = Math.max(500, ...Object.values(water));
    chart.innerHTML = '';
    for (let h = 8; h <= 21; h++) {
      const ml = water[h] || 0;
      const s = document.createElement('span');
      s.innerHTML = `<i class="${ml ? 'f' : ''}" style="height:${Math.max(4, 96 * ml / top)}px"></i>${h % 3 === 0 ? String(h).padStart(2, '0') : '&nbsp;'}`;
      chart.appendChild(s);
    }
    const pct = Math.min(100, Math.round(total / 20));
    $('#waterNow').textContent = (total / 1000).toFixed(total % 1000 ? 1 : 0).replace('.', ',');
    $('#waterPct').textContent = pct + '%';
    $('#waterBar').style.width = pct + '%';
  }
  $('#drinkBtn').addEventListener('click', () => { water[16] = (water[16] || 0) + 250; renderWater(); });
  renderWater();

  // ---------- Klik kecil lainnya ----------
  $$('.todos li').forEach((li) => $('.check', li).addEventListener('click', () => li.classList.toggle('done')));
  $$('.clip li').forEach((li) => $('.pin', li).addEventListener('click', () => li.classList.toggle('pinned')));
  $$('.shortcuts button').forEach((b) => b.addEventListener('click', () => {
    b.classList.add('ran');
    setTimeout(() => b.classList.remove('ran'), 900);
  }));
  let pomoRunning = true, pomoLeft = 15 * 60 + 32;
  $('#pomoBtn').addEventListener('click', () => {
    pomoRunning = !pomoRunning;
    $('#pomoBtn').innerHTML = `<i data-lucide="${pomoRunning ? 'pause' : 'play'}"></i>${pomoRunning ? 'Jeda' : 'Lanjut'}`;
    icons();
  });

  // ---------- Jam dan hitungan ----------
  const day = new Intl.DateTimeFormat('id-ID', { weekday: 'short', day: 'numeric', month: 'short' });
  const time = new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit' });
  const two = (n) => String(n).padStart(2, '0');
  let cdLeft = 7 * 60 + 42;
  function everySecond() {
    const now = new Date();
    const label = `${day.format(now).replace(/,/g, '')} ${time.format(now)}`;
    $('#displayClock').textContent = `${day.format(now).split(' ')[0].replace(',', '')} ${time.format(now)}`;
    $('#headClock').textContent = label;
    if (pomoRunning) pomoLeft = pomoLeft > 0 ? pomoLeft - 1 : 25 * 60;
    $('#pomo').textContent = `${two(Math.floor(pomoLeft / 60))}.${two(pomoLeft % 60)}`;
    $('#pomoRing').setAttribute('stroke-dasharray', `${(100 - pomoLeft / 15).toFixed(1)} 100`);
    cdLeft = cdLeft > 0 ? cdLeft - 1 : 600;
    $('#cd1').textContent = `${two(Math.floor(cdLeft / 60))}.${two(cdLeft % 60)}`;
    $('#cdRing').setAttribute('stroke-dasharray', `${(100 - cdLeft / 6).toFixed(1)} 100`);
    if (playing) seek = seek < 220 ? seek + 1 : 0;
    $('#seekPos').textContent = `${Math.floor(seek / 60)}.${two(seek % 60)}`;
    $('#seekBar').style.width = (seek / 220 * 100).toFixed(1) + '%';
  }
  setInterval(everySecond, 1000);
  const swStart = performance.now() - 42300;
  setInterval(() => {
    if (N.dataset.view !== 'open' || page !== 'clock') return;
    const t = (performance.now() - swStart) / 1000;
    $('#stopwatch').textContent = `${two(Math.floor(t / 60) % 60)}:${two(Math.floor(t) % 60)}.${Math.floor(t * 10) % 10}`;
  }, 100);

  // ---------- Versi terbaru dan catatan rilis dari GitHub ----------
  fetch('https://api.github.com/repos/reinharddev/cognify-notch/releases?per_page=3')
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((releases) => {
      if (!Array.isArray(releases) || !releases.length) return;
      const latest = releases[0];
      const dmg = (latest.assets || []).find((a) => a.name.endsWith('.dmg'));
      const version = latest.tag_name.replace(/^v/, '');
      if (dmg) $$('.dl').forEach((a) => { a.href = dmg.browser_download_url; });
      $$('.ver').forEach((s) => { s.textContent = 'Versi ' + version; });
      const list = $('#changeList');
      const date = new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'long', year: 'numeric' });
      releases.forEach((rel) => {
        const box = document.createElement('div');
        box.className = 'rel';
        const head = document.createElement('div');
        head.innerHTML = '<b></b><small></small>';
        head.querySelector('b').textContent = rel.tag_name.replace(/^v/, 'Versi ');
        head.querySelector('small').textContent = date.format(new Date(rel.published_at));
        const ul = document.createElement('ul');
        (rel.body || '').split('\n').map((l) => l.trim()).filter(Boolean).forEach((line) => {
          const li = document.createElement('li');
          li.textContent = line;
          ul.appendChild(li);
        });
        box.append(head, ul);
        list.appendChild(box);
      });
      $('#changes').hidden = false;
    })
    .catch(() => { /* tautan tetap ke halaman rilis GitHub */ });

  // ---------- Mulai ----------
  icons();
  setPage('home', 0);
  showLyric(0);
  everySecond();
  onScroll();
})();
