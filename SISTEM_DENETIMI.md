# SanalTrader — Uygulama / Bot Bağlantı Denetimi

Denetim: 22 Kasım 2026
Test ortamı: GitHub Actions Flutter stable ve Python 3, main

## Bulunan bağlantı sorunları ve uygulanan düzeltmeler

| Alan | Denetim sonucu | Son uygulanan düzeltme |
|---|---|---|
| Panel | Sunucu botu yalnızca Bot ekranında görünüyordu | Sunucu kasası özeti ve ayrı yerel kasa etiketi eklendi |
| Portföy | Sunucu LONG/SHORT pozisyonları yerel kasaya bağlanmıyordu | Aynı salt okunur sunucu kaydı Portföy ekranına da bağlandı |
| Kâr | Sunucu gerçek sanal sonuçları yerel kârlılık ekranında yoktu | Sunucu performans özeti ve LONG/SHORT kapanış öğrenme istatistiği eklendi |
| İşlem geçmişi | Sunucu geçmişinden yalnızca birkaç işlem görünüyordu | Kaydedilmiş sunucu LONG/SHORT işlemleri için tam sayfa ve yenileme bağlantısı eklendi |
| Bot kontrolü | Tarayıcı botu kullanıcı müdahalesi olmadan açılabiliyordu | Yeni kurulumda yerel bot OFF; mevcut ON/OFF tercihi korunur |
| Emir güvenliği | Aynı sekmedeki yerel manuel/bot kayıtları çakışabilirdi | Sıralı yerel emir ve reset kuyruğu eklendi |
| Zarar koruması | Günlük emir sınırı acil yerel stop satışını engelliyordu | Limit yalnızca yeni yerel emir açmayı engelliyor |
| Veri doğruluğu | Bayat coin fiyatları portföyde güncelmiş gibi görünebilirdi | Güncel olmayan fiyatta yeni AL ve net varlık hesaplaması güvenle durur |
| Sunucu bağlantısı | Public GitHub GET isteğinde CORS preflight riski | Gereksiz Cache-Control header kaldırıldı, cache-busting query korundu |
| Geçmiş sürüm | Ana sayfada eski 0.6.0 güncelleme etiketi bulunuyordu | 0.9.1 olarak güncellendi |
| LONG/SHORT | İşlem yönlerinin görünürlüğü dağınıktı | Açık pozisyonlar, giriş/kapanış ve teminat açıkça ayrı gösterildi |

## Testler ve deploy

- Main Flutter: analyzer, **68 test**, web derlemesi ve GitHub Pages dağıtımı başarıyla tamamlandı (commit `e229a0dc`, son kod denetiminin bir önceki sürümü).
- Sunucu Python: 25 birim testi, önceki güncel bot sürümünde başarılı. Bot canlı borsa emri göndermez.
- Bu raporun oluşturulmasıyla standardize edilen cron değişikliği de ayrı CI ve deploy sonucundan geçmelidir.

## Açık kalan mimari ve operasyonel sınırlamalar

1. **İki ayrı sanal cüzdan var.** GitHub'da çalışan ücretsiz sunucu botunun ayrı 650 TL sanal cüzdanı, tarayıcıdaki yerel 650 TL cüzdandan farklıdır. Uygulamanın sayfaları sunucu değerini okuyup gösterir fakat yerel AL/SAT onu değiştirmez. Verileri birleştirmek gerçek işlemleri silme/kaydırma riski taşır; otomatik birleştirme yapılmadı.
2. **Sunucu botunu uygulamadaki yerel aç/kapat anahtarı yönetmiyor.** Sunucu botunun ayrı GitHub Actions `workflow_dispatch` run/pause/resume/reset menüsü vardır. Gizli Github token'ının herkese açık Flutter web'e konması güvenli değildir. Bu yönetim için ayrı kimlik doğrulamalı servis gerekir.
3. **GitHub Actions tam 7/24 kesintisiz servis değildir.** Her 5 dakikada bir iş başlatmayı *dener*. İşler gecikebilir/atlanabilir; ilk zamanlanmış (event=schedule) çalıştırmanın başarılı gerçekleştiği henüz gözlenmedi. Başarılı bot çalışmaları kod push olaylarından geldi. Bot ekranı son başarılı çalışma zamanı geç kalınca bunu işaretler.
4. **Farklı tarayıcı sekmeleri arasında eşzamanlı yerel emir garantisi yok.** Yerel kilit tek Flutter repository örneği içinde geçerli. Sunucu botunda GitHub concurrency kullanılır.
5. **1x SHORT spot referans fiyatlı bir simülasyondur.** Funding, borçlanma maliyeti, spread, gerçek emir defteri ve gerçek futures likidasyonu tam modellenmez. İki periyodik kontrol arasındaki stop fiyatı garanti değildir.
6. **Bir insanın gerçek tarayıcıda tıklayarak uçtan uca kabul testi henüz gerçekleştirilmedi.** GitHub CI derlemesi ve widget testleri, canlı sayfadaki tüm cihaz/tarayıcı kombinasyonlarını garanti edemez.

## Güvenli test ilkesi

- Gerçek para / kripto borsası anahtarı / para transferi yoktur.
- Hiçbir cüzdan veya işlem geçmişi bu denetimde sıfırlanmadı.
- Sunucu durumu `bot-data/state.json` içerisinde herkese açık ve yalnızca sanal bilgiler taşır.
