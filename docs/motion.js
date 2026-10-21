// Animasi halaman. Bentuk gerakannya ada di style.css (bagian Animasi); file ini hanya
// memasang kelas pada saat yang tepat: judul per kata, bagian yang muncul saat digulir,
// angka yang menghitung, tanya jawab yang terbuka mulus, kursor contoh, dan reaksi navigasi
// saat notch menempel. Tidak berjalan bila "Kurangi gerakan" menyala.
(() => {
  if (!document.documentElement.classList.contains('motion')) return;
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const N = $('#notch');
  const display = $('#display');

  // ---------- 1. Judul pembuka dipecah per kata ----------
  function splitHeadline() {
    const h1 = $('.hero h1');
    let i = 0;
    const walk = (node) => {
      [...node.childNodes].forEach((child) => {
        if (child.nodeType === Node.TEXT_NODE) {
          const parts = child.textContent.split(/(\s+)/);
          const frag = document.createDocumentFragment();
          parts.forEach((part) => {
            if (!part) return;
            if (/^\s+$/.test(part)) { frag.appendChild(document.createTextNode(part)); return; }
            const w = document.createElement('span');
            w.className = 'w';
            const inner = document.createElement('span');
            inner.style.setProperty('--i', i++);
            inner.textContent = part;
            w.appendChild(inner);
            frag.appendChild(w);
          });
          child.replaceWith(frag);
        } else if (child.nodeType === Node.ELEMENT_NODE && child.tagName !== 'BR') {
          if (child.classList.contains('hl')) child.style.setProperty('--hl', (.15 + i * .07 + .15) + 's');
          walk(child);
        }
      });
    };
    walk(h1);
  }
  splitHeadline();

  // ---------- 2. Notch baru muncul setelah layar laptop menyala ----------
  // Selama layar laptop masih berputar terbuka, posisinya belum benar; notch disembunyikan
  // dan posisinya dihitung ulang begitu layar selesai terbuka.
  const lid = $('.lid');
  const settle = () => { window.dispatchEvent(new Event('scroll')); N.classList.remove('boot'); };
  if (display.getBoundingClientRect().top > 0) N.classList.add('boot');
  lid.addEventListener('animationend', settle, { once: true });
  setTimeout(settle, 2200);

  // ---------- 3. Bukit dan matahari mengikuti posisi mouse ----------
  const hero = $('.hero');
  if (matchMedia('(hover: hover)').matches) {
    let frame = 0;
    hero.addEventListener('pointermove', (e) => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        const r = display.getBoundingClientRect();
        const mx = Math.max(-1, Math.min(1, ((e.clientX - r.left) / r.width) * 2 - 1));
        const my = Math.max(-1, Math.min(1, ((e.clientY - r.top) / r.height) * 2 - 1));
        display.style.setProperty('--mx', mx.toFixed(3));
        display.style.setProperty('--my', my.toFixed(3));
      });
    });
    hero.addEventListener('pointerleave', () => {
      display.style.setProperty('--mx', 0);
      display.style.setProperty('--my', 0);
    });
  }

  // ---------- Bagian yang muncul saat digulir ----------
  const groups = [
    ['.steps-head > *'], ['.block > h2'], ['.block > .lead'], ['.sub'], ['.note'],
    ['.gestures > div', true], ['.net > div', true], ['.local li', true], ['.perms span', true],
    ['.facts > div', true], ['.spec li', true], ['.faq details', true], ['footer > span', true], ['.flow.stay'],
  ];
  const seen = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('in');
      seen.unobserve(entry.target);
      if (entry.target.matches('.facts > div')) countUp($('b', entry.target), parseFloat(entry.target.style.getPropertyValue('--d')) || 0);
    });
  }, { rootMargin: '0px 0px -12% 0px' });
  groups.forEach(([sel, stagger]) => {
    $$(sel).forEach((el, k) => {
      if (!el.matches('.flow')) el.classList.add('rv');
      if (stagger) el.style.setProperty('--d', Math.min(k, 6) * 0.07 + 's');
      seen.observe(el);
    });
  });

  // ---------- 13. Angka spesifikasi menghitung; 0 menghitung mundur dari 9 ----------
  function countUp(el, delay) {
    const match = el.textContent.match(/^(\d+)(.*)$/);
    if (!match) return;
    const target = +match[1];
    const suffix = match[2];
    const from = target === 0 ? 9 : 0;
    el.textContent = from + suffix;
    setTimeout(() => {
      const start = performance.now();
      const tick = (now) => {
        const t = Math.min(1, (now - start) / 1100);
        const eased = 1 - Math.pow(1 - t, 3);
        el.textContent = Math.round(from + (target - from) * eased) + suffix;
        if (t < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    }, delay * 1000 + 200);
  }

  // ---------- 15. Blok unduh membuka saat sepertiganya terlihat ----------
  // Yang diamati bagian pembungkusnya: blok yang sedang terpotong clip-path dianggap
  // hampir tidak terlihat oleh IntersectionObserver.
  const getNotch = $('.get-notch');
  new IntersectionObserver((entries, obs) => {
    if (!entries[0].isIntersecting) return;
    getNotch.classList.add('in');
    obs.disconnect();
  }, { rootMargin: '0px 0px -35% 0px' }).observe($('#unduh'));

  // ---------- 14. Tanya jawab terbuka dan tertutup mulus ----------
  $('.faq').addEventListener('click', (e) => {
    const summary = e.target.closest('summary');
    if (!summary) return;
    const box = summary.parentElement;
    const body = $('p', box);
    if (!body) return;
    e.preventDefault();
    if (box._anim) box._anim.cancel();
    const style = getComputedStyle(body);
    const margin = style.marginBottom;
    if (box.open) {
      const anim = body.animate([
        { height: body.offsetHeight + 'px', marginBottom: margin, opacity: 1 },
        { height: '0px', marginBottom: '0px', opacity: 0 },
      ], { duration: 260, easing: 'cubic-bezier(.4, 0, .2, 1)' });
      box._anim = anim;
      box.classList.add('closing');
      anim.onfinish = () => { box.open = false; box.classList.remove('closing'); box._anim = null; };
    } else {
      box.open = true;
      const anim = body.animate([
        { height: '0px', marginBottom: '0px', opacity: 0 },
        { height: body.offsetHeight + 'px', marginBottom: margin, opacity: 1 },
      ], { duration: 320, easing: 'cubic-bezier(.2, .9, .3, 1)' });
      box._anim = anim;
      anim.onfinish = () => { box._anim = null; };
    }
  });

  // ---------- 6. Pil navigasi menyambut notch yang menempel ----------
  const nav = $('.nav');
  window.addEventListener('notch:dock', (e) => {
    if (!e.detail) return;
    nav.classList.remove('catch');
    void nav.offsetWidth;
    nav.classList.add('catch');
  });
  nav.addEventListener('animationend', () => nav.classList.remove('catch'));

  // ---------- 7. Notch memantul setiap kali berubah bentuk ----------
  const shell = $('.shell', N);
  window.addEventListener('notch:view', () => {
    shell.classList.remove('squish');
    void shell.offsetWidth;
    shell.classList.add('squish');
  });

  // ---------- 4. Kursor contoh ----------
  // Muncul 4 detik setelah halaman terbuka bila pengunjung belum menyentuh notch, lalu
  // tiap 14 detik, paling banyak 3 kali. Berhenti selamanya begitu notch dicoba sendiri.
  const ghost = $('#ghost');
  let tried = false, runs = 0, running = false;
  const stopGhost = () => {
    tried = true;
    if (running) {
      ghost.classList.remove('on', 'press');
      N.dispatchEvent(new PointerEvent('pointerleave', { pointerType: 'mouse' }));
      running = false;
    }
  };
  N.addEventListener('pointerenter', (e) => { if (e.isTrusted) stopGhost(); });
  N.addEventListener('pointerdown', (e) => { if (e.isTrusted) stopGhost(); });
  const wait = (ms) => new Promise((done) => setTimeout(done, ms));
  const place = (x, y) => { ghost.style.left = x + 'px'; ghost.style.top = y + 'px'; };

  async function demo() {
    const r = display.getBoundingClientRect();
    // Hanya saat notch masih di layar laptop dan layar itu cukup terlihat.
    const heroVisible = r.top > 0 && r.top < window.innerHeight - 220;
    if (tried || running || !heroVisible || document.hidden) return;
    running = true;
    runs++;
    ghost.style.transition = 'none';
    place(r.left + r.width * 0.72, r.top + r.height * 0.78);
    void ghost.offsetWidth;
    ghost.style.transition = '';
    ghost.classList.add('on');
    await wait(450);
    // Ujung kursor di tengah notch tertutup, di tepi atas layar laptop.
    place(r.left + r.width * 0.5 + 4, r.top + Math.max(6, 14 * (parseFloat(N.style.getPropertyValue('--s')) || 1)));
    await wait(1200);
    if (tried) return;
    ghost.classList.add('press');
    N.dispatchEvent(new PointerEvent('pointerenter', { pointerType: 'mouse' }));
    await wait(350);
    ghost.classList.remove('press');
    await wait(2600);
    if (tried) return;
    place(r.left + r.width * 0.58, r.top + r.height * 0.86);
    await wait(500);
    N.dispatchEvent(new PointerEvent('pointerleave', { pointerType: 'mouse' }));
    await wait(700);
    ghost.classList.remove('on');
    running = false;
  }
  setTimeout(function loop() {
    demo();
    if (!tried && runs < 3) setTimeout(loop, 14000);
  }, 4000);

  // ---------- Ganti bahasa: judul dipecah lagi dan ikon digambar ulang ----------
  window.I18N.onChange(() => splitHeadline());
})();
