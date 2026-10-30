// English and Turkish. The choice is remembered; the first visit follows the browser's language.
(() => {
  const strings = {
    en: {
      "meta.title": "NotchOne", "meta.description": "NotchOne turns the MacBook notch into a home for what's playing, the weather, files, translation and system stats. Free, with no accounts or tracking.",
      "nav.home": "Home", "nav.features": "Features", "nav.privacy": "Privacy", "nav.support": "Feedback", "nav.download": "Download", "privacy.href": "privacy.html", "nav.terms": "Terms", "terms.href": "terms.html",
      "hero.tag": "Free for your MacBook", "hero.title": "Your notch,<br>doing something useful.",
      "hero.lead": "NotchOne shows what's playing, the weather, your devices, files and running jobs right in the MacBook notch. Free, with no accounts and no tracking.",
      "hero.cta": "Download for macOS", "hero.more": "See what it does", "hero.note": "Version 1.0.0, 4.8 MB. macOS 26 or later. Signed and notarized.",
      "demo.menu1": "File", "demo.menu2": "Edit", "demo.menu3": "View", "demo.on": "On", "demo.cloudy": "Cloudy", "demo.battery": "Battery",
      "demo.hint": "Try it:", "demo.music": "Music", "demo.volume": "Volume", "demo.focus": "Focus", "demo.note": "Notification", "demo.noteTitle": "Ada: Lunch?", "demo.noteBody": "See you at one.", "demo.charge": "Charging", "demo.open": "Open",
      "demo.home": "Home", "demo.weather": "Weather", "demo.system": "System", "demo.translate": "Translate", "demo.notes": "Notes",
      "demo.label": "A working notch demo", "demo.try": "Try the notch",
      "marquee": "Now Playing,Weather,Shelf,AirDrop,Translate,Clipboard,Search,System,Device batteries,Notes,Notifications,Focus,Volume,Brightness,Mirror",
      "ch.label": "Features", "shape.notch": "Notch", "shape.pill": "Pill",
      "ch.home.name": "Home", "ch.home.title": "Everything at a glance", "ch.home.text": "Music, weather, battery and your devices in one view. Move the cards around or keep only the ones you use.",
      "ch.nowplaying.name": "Now Playing", "ch.nowplaying.title": "Your music, up top", "ch.nowplaying.text": "Music, Spotify and browsers, with controls and the album colour. Click the cover to jump to the app that's playing.",
      "ch.weather.name": "Weather", "ch.weather.title": "The forecast in the notch", "ch.weather.text": "Now, today and the days ahead, in your language and your units.",
      "ch.system.name": "System", "ch.system.title": "Your Mac and its devices", "ch.system.text": "CPU, memory and network with a minute of history, plus the battery of your AirPods, keyboard and mouse.",
      "ch.translate.name": "Translate", "ch.translate.title": "Translate anything", "ch.translate.text": "⌃⌥T translates the selection in any app, on-device with Apple's models.",
      "ch.drop.name": "Drop", "ch.drop.title": "Drop files on the notch", "ch.drop.text": "Keep them on the Shelf, AirDrop them, or convert and compress images and PDFs.",
      "ch.notes.name": "Notes", "ch.notes.title": "A scratchpad that's always there", "ch.notes.text": "It saves as you type and stays on your Mac.",
      "ch.alert.name": "Alerts", "ch.alert.title": "Read it without leaving", "ch.alert.text": "A notification opens under the notch, with the app, the sender and the message. Click it to go to the app.",
      "ch.notifications.name": "Notifications", "ch.notifications.title": "Never miss a notification", "ch.notifications.text": "They open under the notch and stay in their own tab, so you can read them later.",
      "ch.compact.name": "Compact", "ch.compact.title": "Just one row", "ch.compact.text": "Compact mode keeps the notch small when you want less on screen.",
      "ch.settings.name": "Settings", "ch.settings.title": "Settings, right there", "ch.settings.text": "Everything is set up inside the notch, so you never leave what you're doing.",
      "ch.tour.name": "Tour", "ch.tour.title": "A short tour to start", "ch.tour.text": "The first launch shows you around, and each permission waits for your click.",
      "more.title": "And it doesn't stop there.", "more.search": "Search", "more.searchText": "Looks through your clipboard, shelf and tabs.", "search.demo": "invoice.pdf",
      "more.noteBubble": "New message", "more.note": "Notifications", "more.noteText": "Every notification shows in the notch, and you can read it later in its own tab.",
      "more.battery": "Device batteries", "more.batteryText": "AirPods, keyboard and mouse, and a warning when one runs low.",
      "more.perm": "You decide", "more.permText": "Nothing asks for permission on launch. Each one waits for your click in the tour.",
      "more.colour": "The album's colour", "more.colourText": "The notch takes on the colour of what you're listening to.",
      "end.title": "Make your notch work.", "end.text": "No accounts and no analytics in the app. The weather gets your area rounded to about 1 km; everything else stays on your Mac.", "end.weather": "Weather data by", "end.github": "View on GitHub", "end.brands": "Apple, Mac, MacBook, AirPods and Spotify are trademarks of their owners. NotchOne isn't affiliated with them.",
      "feedback.title": "NotchOne Feedback", "feedback.heading": "Tell me what you think.", "feedback.lead": "Found a bug, missing a feature, or just want to say hi? Your message comes straight to me.",
      "feedback.kind": "What's it about?", "feedback.bug": "Bug", "feedback.idea": "Idea", "feedback.question": "Question", "feedback.other": "Other", "feedback.message": "Your message",
      "feedback.empty": "Write a message first.", "feedback.send": "Open in my mail app", "feedback.note": "This opens your mail app with the message ready. Nothing is sent until you press send there.",
      "feedback.direct": "Or reach me directly", "feedback.mail": "Email", "feedback.copy": "Copy", "feedback.copied": "Copied", "feedback.linkedin": "Connect with me",
    },
    tr: {
      "meta.title": "NotchOne", "meta.description": "NotchOne, MacBook notch'unu çalan müziğin, hava durumunun, dosyaların, çevirinin ve sistem bilgilerinin evine dönüştürür. Ücretsiz, hesap ve takip yok.",
      "nav.home": "Ana Sayfa", "nav.features": "Özellikler", "nav.privacy": "Gizlilik", "nav.support": "Geri Bildirim", "nav.download": "İndir", "privacy.href": "privacy-tr.html", "nav.terms": "Kullanım Şartları", "terms.href": "terms-tr.html",
      "hero.tag": "MacBook'un için ücretsiz", "hero.title": "Notch'un artık<br>işe yarıyor.",
      "hero.lead": "NotchOne çalan müziği, hava durumunu, cihazlarını, dosyalarını ve devam eden işlerini MacBook notch'unda gösterir. Ücretsiz, hesap yok, takip yok.",
      "hero.cta": "macOS için indir", "hero.more": "Neler yapıyor?", "hero.note": "Sürüm 1.0.0, 4,8 MB. macOS 26 veya üstü. İmzalı ve onaylı.",
      "demo.menu1": "Dosya", "demo.menu2": "Düzen", "demo.menu3": "Görünüm", "demo.on": "Açık", "demo.cloudy": "Bulutlu", "demo.battery": "Pil",
      "demo.hint": "Dene:", "demo.music": "Müzik", "demo.volume": "Ses", "demo.focus": "Odak", "demo.note": "Bildirim", "demo.noteTitle": "Ada: Öğle yemeği?", "demo.noteBody": "Birde görüşürüz.", "demo.charge": "Şarj", "demo.open": "Aç",
      "demo.home": "Ana Sayfa", "demo.weather": "Hava", "demo.system": "Sistem", "demo.translate": "Çeviri", "demo.notes": "Notlar",
      "demo.label": "Çalışan bir notch demosu", "demo.try": "Notch'u dene",
      "marquee": "Şimdi Çalıyor,Hava Durumu,Raf,AirDrop,Çeviri,Pano,Arama,Sistem,Cihaz pilleri,Notlar,Bildirimler,Odak,Ses,Parlaklık,Ayna",
      "ch.label": "Özellikler", "shape.notch": "Notch", "shape.pill": "Hap",
      "ch.home.name": "Ana Sayfa", "ch.home.title": "Her şey tek bakışta", "ch.home.text": "Müzik, hava durumu, pil ve cihazların tek ekranda. Kartların yerini değiştir veya sadece kullandıklarını bırak.",
      "ch.nowplaying.name": "Şimdi Çalıyor", "ch.nowplaying.title": "Müziğin hep üstte", "ch.nowplaying.text": "Music, Spotify ve tarayıcılar; kontroller ve albüm rengiyle. Kapağa tıkla, çalan uygulamaya geç.",
      "ch.weather.name": "Hava", "ch.weather.title": "Hava durumu notch'ta", "ch.weather.text": "Şimdi, bugün ve önümüzdeki günler; senin dilinde ve senin birimlerinde.",
      "ch.system.name": "Sistem", "ch.system.title": "Mac'in ve cihazların", "ch.system.text": "Bir dakikalık geçmişle CPU, bellek ve ağ; ayrıca AirPods, klavye ve farenin pili.",
      "ch.translate.name": "Çeviri", "ch.translate.title": "Her şeyi çevir", "ch.translate.text": "⌃⌥T, herhangi bir uygulamadaki seçili metni Apple'ın cihaz içi modelleriyle çevirir.",
      "ch.drop.name": "Bırak", "ch.drop.title": "Dosyaları notch'a bırak", "ch.drop.text": "Rafta tut, AirDrop ile gönder ya da görselleri ve PDF'leri dönüştür ve sıkıştır.",
      "ch.notes.name": "Notlar", "ch.notes.title": "Hep elinin altında bir not defteri", "ch.notes.text": "Yazarken kaydeder ve Mac'inde kalır.",
      "ch.alert.name": "Uyarılar", "ch.alert.title": "İşini bırakmadan oku", "ch.alert.text": "Bildirim notch'un altında açılır; uygulama, gönderen ve mesaj görünür. Tıklayınca uygulamaya geçersin.",
      "ch.notifications.name": "Bildirimler", "ch.notifications.title": "Hiçbir bildirimi kaçırma", "ch.notifications.text": "Notch'un altında açılır ve kendi sekmesinde durur, sonra okuyabilirsin.",
      "ch.compact.name": "Kompakt", "ch.compact.title": "Tek satır yeter", "ch.compact.text": "Ekranda daha az şey istediğinde kompakt mod notch'u küçük tutar.",
      "ch.settings.name": "Ayarlar", "ch.settings.title": "Ayarlar da burada", "ch.settings.text": "Her şey notch'un içinden ayarlanır, yaptığın işi bırakmana gerek kalmaz.",
      "ch.tour.name": "Tur", "ch.tour.title": "Başlangıçta kısa bir tur", "ch.tour.text": "İlk açılışta her şeyi gösterir, her izin de senin tıklamanı bekler.",
      "more.title": "Bununla da bitmiyor.", "more.search": "Arama", "more.searchText": "Panonda, rafında ve sekmelerinde arar.", "search.demo": "fatura.pdf",
      "more.noteBubble": "Yeni mesaj", "more.note": "Bildirimler", "more.noteText": "Her bildirim notch'ta görünür, sonra kendi sekmesinden okuyabilirsin.",
      "more.battery": "Cihaz pilleri", "more.batteryText": "AirPods, klavye ve fare; pil azaldığında da uyarı.",
      "more.perm": "Karar senin", "more.permText": "Açılışta hiçbir izin sorulmaz. Her biri turda senin tıklamanı bekler.",
      "more.colour": "Albümün rengi", "more.colourText": "Notch, dinlediğin şarkının rengini alır.",
      "end.title": "Notch'unu çalıştır.", "end.text": "Uygulamada hesap ve analitik yok. Hava durumu servisi bölgeni yaklaşık 1 km'ye yuvarlanmış görür; geri kalan her şey Mac'inde kalır.", "end.weather": "Hava durumu verisi:", "end.github": "GitHub'da gör", "end.brands": "Apple, Mac, MacBook, AirPods ve Spotify sahiplerinin markalarıdır. NotchOne'ın onlarla bir bağlantısı yoktur.",
      "feedback.title": "NotchOne Geri Bildirim", "feedback.heading": "Ne düşündüğünü söyle.", "feedback.lead": "Bir hata mı buldun, bir özellik mi eksik, yoksa sadece selam mı vermek istiyorsun? Mesajın doğrudan bana gelir.",
      "feedback.kind": "Konu ne?", "feedback.bug": "Hata", "feedback.idea": "Fikir", "feedback.question": "Soru", "feedback.other": "Diğer", "feedback.message": "Mesajın",
      "feedback.empty": "Önce bir mesaj yaz.", "feedback.send": "Mail uygulamamda aç", "feedback.note": "Mail uygulaman mesaj hazır şekilde açılır. Oradan göndermeden hiçbir şey gitmez.",
      "feedback.direct": "Ya da doğrudan ulaş", "feedback.mail": "E-posta", "feedback.copy": "Kopyala", "feedback.copied": "Kopyalandı", "feedback.linkedin": "Benimle bağlantı kur",
    },
  };

  const root = document.documentElement;
  const read = () => { try { return localStorage.getItem("lang"); } catch { return null; } };
  const write = (lang) => { try { localStorage.setItem("lang", lang); } catch { /* private window */ } };
  const page = strings[root.lang] && root.dataset.alt ? root.lang : null; // a page that exists in one language
  let current = read() || (navigator.language.toLowerCase().startsWith("tr") ? "tr" : "en");

  const text = (key) => strings[current][key] ?? strings.en[key] ?? "";
  window.t = text;

  function apply() {
    root.lang = current;
    document.title = text(root.dataset.title ?? "meta.title");
    if (!root.dataset.title) document.querySelector('meta[name="description"]')?.setAttribute("content", text("meta.description"));
    document.querySelectorAll("[data-i18n]").forEach((node) => {
      const value = text(node.dataset.i18n);
      if (value.includes("<br>")) node.innerHTML = value;
      else node.textContent = value;
    });
    document.querySelectorAll("[data-i18n-href]").forEach((node) => node.setAttribute("href", text(node.dataset.i18nHref)));
    document.querySelectorAll("[data-i18n-label]").forEach((node) => node.setAttribute("aria-label", text(node.dataset.i18nLabel)));
    document.querySelectorAll("[data-lang]").forEach((button) => button.setAttribute("aria-pressed", button.dataset.lang === current));
    document.querySelectorAll(".lang").forEach((group) => group.classList.toggle("is-tr", current === "tr"));
  }

  function choose(lang) {
    if (lang === current) return;
    write(lang);
    if (page) {
      location.href = root.dataset.alt;
      return;
    }
    current = lang;
    document.body.classList.add("is-switching");
    setTimeout(() => {
      apply();
      dispatchEvent(new CustomEvent("langchange"));
      document.body.classList.remove("is-switching");
    }, 200);
  }

  if (page) {
    // This page is written in one language: only its shared parts are translated here.
    if (current !== page) { location.replace(root.dataset.alt); return; }
    current = page;
    document.querySelectorAll("[data-i18n]").forEach((node) => { node.textContent = text(node.dataset.i18n); });
    document.querySelectorAll("[data-i18n-href]").forEach((node) => node.setAttribute("href", text(node.dataset.i18nHref)));
    document.querySelectorAll("[data-lang]").forEach((button) => button.setAttribute("aria-pressed", button.dataset.lang === current));
    document.querySelectorAll(".lang").forEach((group) => group.classList.toggle("is-tr", current === "tr"));
  } else {
    apply();
  }
  document.querySelectorAll("[data-lang]").forEach((button) => button.addEventListener("click", () => choose(button.dataset.lang)));
})();
