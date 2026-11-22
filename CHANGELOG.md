# SanalTrader — Güncelleme Geçmişi

Bu dosya sürümlerin kalıcı, okunabilir kaydıdır. Uygulamanın **Güncelleme Geçmişi** ekranı aynı sürüm bilgilerini `assets/changelog.json` üzerinden okur.

## v0.4.0 — 2026-11-22: Teknik analiz ve uzman karar destek sistemi

- RSI/MACD/EMA ve saatlik mum yorumlarının sonuçlarıyla sınırlı teknik güven ağırlığı güncellenir.
- Coin ekranına gerçek tamamlanmış OHLCV grafiği ve göstergelerin açıklaması eklendi.
- Bot arayüzü Bitcoin piyasa rejimini, gerilemeyi, strateji ağırlıklarını ve teknik doğruluğu gösterir.

- RSI(14), EMA20/50, MACD(12/26/9), destek ve direnç, 24 saatlik oynaklık ve ATR analizleri eklendi.
- Tamamlanmış saatlik OHLCV mumlarından yutan mum, çekiç ve uzun üst fitil gibi formasyonlar yorumlanıyor.
- Canlı bot, teknik sinyallerin yanında Bitcoin piyasa yönünü ve volatiliteyi dikkate alarak sanal pozisyon miktarını ayarlıyor.
- Portföyde %12 zirveye göre gerilemede yeni sanal alışları durduracak koruma eklendi.
- Her teknik yorumun nedenleri, risk uyarıları ve veri kalitesi kullanıcıya gösteriliyor.
- Uygulama içi Güncelleme Geçmişi ekranı, sürüm notları ve değişiklik kaydını zorunlu tutan kontrol eklendi.
- OHLCV verisi geçmiş saatlerdeki gerçek TRY kuru değildir; güncel USDT/TRY ile dönüştürülen yaklaşık TRY grafiğidir.

## v0.3.0 — 2026-11-22: Altcoin evreni ve geçmişten öğrenme

- Binance Spot'ta 24 saatlik hacme göre en fazla 72 likit USDT çifti taranıyor.
- Likiditesi düşük, stablecoin ve isimden belirlenen kaldıraçlı ürünler eleniyor.
- En likit 36 paranın saatlik geçmişi alınarak strateji eğitimine sunuluyor.
- Son 24 saat eğitim dışında tutularak tahmin doğruluğu ayrı bir testte ölçülüyor.
- Bot yetersiz geçmiş veri varsa yeni alış açmadan bekliyor.
- Piyasa arama, hacme göre sıralama ve çok küçük TRY fiyatlarında hassas gösterim eklendi.
- Binance erişimi olmazsa CoinGecko'dan filtrelenmiş geniş yedek piyasa listesi deneniyor.

## v0.2.1 — 2026-11-22: Canlı piyasa akışı ve bot sinyalleri

- Binance miniTicker WebSocket üzerinden kripto fiyatları akıyor.
- USDT/TRY çiftinin gerçek piyasa fiyatıyla TRY simülasyon dönüşümü yapılıyor.
- Bağlantı kesintisinde yeniden bağlanma ve REST fiyat yedeği eklendi.
- 45 saniyede bir sanal bot değerlendirmesi ve Bot sekmesinde canlı AL/BEKLE/negatif sinyaller eklendi.
- Eski veriyle alım engeli ve tarayıcı açıkken çalışma sınırı belirtildi.

## v0.2.0 — 2026-11-22: Öğrenen sanal işlem botu

- Üç stratejili çevrim içi ağırlıklandırma ve daha sonraki fiyatla tahmin doğrulaması eklendi.
- Bot açma/kapatma ve otomatik sanal AL/SAT kontrolleri yapıldı.
- Günlük en fazla 8 emir, tek pozisyon ve toplam maruziyet sınırları eklendi.
- Yaklaşık %6 zarar koruması, %8 kâr alma, işlem günlüğü ve öğrenme ölçümleri hazırlandı.
- Bot işlemleri manuel işlemlerle aynı doğrulama ve sanal cüzdan motorunu kullanıyor.

## v0.1.2 — 2026-11-22: Web yayın sistemi ve test iyileştirmeleri

- GitHub Pages üzerinden doğrudan tarayıcıdan açılan SanalTrader sitesi oluşturuldu.
- Web yayınında artifact erişim hatası giderildi.
- Flutter kod analizi, testler ve web derlemesi GitHub Actions ile kontrol ediliyor.

## v0.1.1 — 2026-11-22: GitHub ve Codespaces geliştirme ortamı

- ashina61/sanal-trader GitHub deposuna Flutter kaynak kodları aktarıldı.
- Codespaces tarayıcı geliştirme ayarları, web önizleme ve VS Code görevleri eklendi.
- APK üretimi isteğe bağlı manuel işlem hâline getirildi.

## v0.1.0 — 2026-11-22: İlk sanal trading prototipi

- ₺650 başlangıç sanal bakiyesi, BTC/ETH/SOL/XRP/BNB/DOGE ile piyasa ekranı kuruldu.
- Tamamen sanal AL/SAT, %0,1 varsayımsal komisyon ve bakiye doğrulaması eklendi.
- Portföy, maliyet, gerçekleşmiş kâr/zarar, işlem geçmişi ve sıfırlama hazırlandı.
- Yerel tarayıcı saklama ve isteğe bağlı Firebase/Firestore altyapısı eklendi.
- İlk sanal emir motoru birim testleri oluşturuldu.

## GitHub geçmişi — 22.11.2026

Aşağıdaki gerçek GitHub commitleri önceki geliştirmeleri belgeliyor (en yeni en başta):

- `c2a45eca` Teknik sinyallerin ileri tarihli piyasa sonucu üzerinden kalibrasyonu ve testler
- `0d72dd52` Teknik güven ağırlığının öğrenilmesi ve saklanması
- `c4ba3cf4` RSI, MACD, OHLCV ve risk freni otomatik testleri
- `bdbfb5a0` Bitcoin piyasa rejimi ve portföy düşüş göstergesi
- `e069a4b3` Mum grafiği ve coin başına ayrıntılı teknik analiz
- `9ace7ea8` Güncelleme Geçmişi ekranı ve sürüm notları
- `44bea0a3` Teknik gösterge, volatilite, BTC rejimi ve portföy gerilemesine göre sanal alım kontrolü
- `cb2cd0b9` Tamamlanmış gerçek Binance OHLCV mumlarının analize bağlanması
- `af964df0` Teknik göstergelerin ilk yorumlama motoru

- `8b2c996b` Geçmiş eğitim ve ayrı doğrulama testinin doğru başlangıç ağırlıkları
- `557e08b4` Geniş CoinGecko yedek listesi birim testi
- `aa73a6fe` Geniş yedek piyasa listesi
- `18ce6231` Eğitim verisi yoksa kontrollü yeniden deneme
- `b20db05f` Canlı fiyatla geçmiş grafik verisinin birleştirilmesi
- `3b2d8653` Geniş altcoin listesinin dokümantasyonu ve küçük fiyat hassasiyeti
- `a777bb23` Hacim filtresi ve veri sızıntısız eğitim testleri
- `eb0328f7` Eğitimde geleceğe bakmayı engelleyen düzeltme
- `9775dbaf` Eğitim doğruluğu ve bot sinyal paneli
- `208ca59b` Coin arama ve gerçek hacme göre sıralama
- `0ad9b285` Eğitimden sonra sanal alış yapma kontrolü
- `b011b1cb` Zaman sıralı geçmiş eğitim ve ayrık doğrulama
- `6d4f7c21` Likit USDT çiftleri için canlı izleme
- `76c49b3e` Uygun coin keşfi
- `01a6d0a5` Eski fiyatla işlem engeli, arka plan tarayıcı kontrolü
- `a230fe36` Binance fiyat verisi ve alternatif REST veri kaynağı
- `aacb5c12` İlk çevrim içi öğrenen sanal bot
- `a962fb83` GitHub Pages yayın hatası düzeltmesi
- `09277c92` GitHub Pages site dağıtımı
- `e5e69aee` Codespaces geliştirme sistemi
- `9460ef27` SanalTrader Flutter prototipi
- `d199fab4` İlk proje deposu

İlgili teknik ayrıntılar için ayrıca [ALTCOIN_EGITIM.md](ALTCOIN_EGITIM.md) ve [CANLI_TRADING.md](CANLI_TRADING.md) dosyalarına bakın.

**Sürüm notu kuralı:** Bundan sonraki kullanıcıya görünen her uygulama özelliği, hata düzeltmesi veya davranış değişikliği aynı committe hem bu dosyada hem `assets/changelog.json` içinde belirtilmelidir. GitHub CI bunu kontrol eder.
