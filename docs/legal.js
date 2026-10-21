// Halaman hukum: pilihan bahasa sama dengan halaman utama (localStorage "lang" atau ?lang=).
(() => {
  const html = document.documentElement;
  const titles = {
    'privasi.html': { id: 'Kebijakan privasi Cognify Notch', en: 'Cognify Notch privacy policy' },
    'syarat.html': { id: 'Syarat penggunaan Cognify Notch', en: 'Cognify Notch terms of use' },
  };
  const page = location.pathname.split('/').pop() || '';
  const apply = (lang) => {
    html.lang = lang;
    if (titles[page]) document.title = titles[page][lang];
    document.getElementById('langBtn').setAttribute('aria-label', lang === 'en' ? 'Ganti ke Bahasa Indonesia' : 'Switch to English');
  };
  document.getElementById('langBtn').addEventListener('click', () => {
    const next = html.lang === 'en' ? 'id' : 'en';
    try { localStorage.setItem('lang', next); } catch (e) { /* tanpa penyimpanan */ }
    apply(next);
  });
  apply(html.lang === 'en' ? 'en' : 'id');
  if (window.lucide) window.lucide.createIcons();
})();
