# SanalTrader — tek beyin, tek sanal kasa

**Canlı uygulama:** https://ashina61.github.io/sanal-trader/

Bu uygulama **gerçek kripto borsasına emir göndermez ve gerçek para kullanmaz**.
Yalnızca başlangıç değeri **650 TL** olan tek bir sanal portföyü takip eder.

## Nasıl çalışıyor?

1. GitHub Actions içindeki `Free Scheduled Paper Bot` Python motoru,
   Binance'ten güncel kamuya açık USDT/TRY kurunu ve likit spot coin verilerini okur.
2. Her taranan aday için saatlik trendi, **gerçek kapanmış 15 dakikalık ve 1 dakikalık mumları**
   analiz eder. Groq AI yalnızca risk motorunun onayladığı AL/SHORT giriş
   adaylarını seçebilir veya BEKLE diyebilir.
3. Normal SPOT AL, SPOT SAT, 1x sanal SHORT AÇ ve SHORT KAPAT kararları tek sunucu cüzdanının
   `bot-data/state.json` kaydına işlenir. Stop, teminat ve zorunlu koruyucu
   çıkışlar AI onayına bağlı değildir.
4. Web ve Android arayüzü sunucu cüzdanını **salt okunur** olarak gösterir.
   **Başka demo cüzdanı, yerel bot, manuel emir veya Firebase hesabı yoktur.**

**Ekranlar:** Kasa (net bakiye ve açık pozisyonlar), Radar (gerçek bot adayları
ve ret gerekçeleri), Bot (son karar ve AI durumu), Kâr (net büyüme ve kapanışlar).

## Öğrenen piyasa ve haber takibi (v0.9.14)

- Binlerce gerçek coin fiyatından likidite elemesi yapılır. Kısa liste için
  1dk, 15dk ve saatlik mumlar ayrı ayrı değerlendirilir. Son 24 saatteki
  yükselen/düşen coin sayıları ve ortanca değişim tek sunucu durumuna yazılır.
- CoinDesk ve Cointelegraph'ın **ücretsiz RSS** yayınları yaklaşık 20 dakikada
  bir sorgulanır. Başlık, kaynak, yayın zamanı ve bağlantı doğrulanır; en
  fazla 6 saatlik başlıklar gösterilir. Kaynak yetersizse haberler uydurulmaz.
- Son 2 saatte ilgili coinde hack, delist, iflas vb. kritik başlık varsa o
  coin için **yeni** giriş durdurulur; yalnızca piyasa çapında iki bağımsız
  kaynaktan risk haberi varsa genel yeni giriş engellenebilir. Haber tek başına
  AL, SAT, SHORT veya kapatma emri vermez. Başlıkların doğru olup olmadığı
  ayrıca doğrulanmalıdır.
- Motor, girişteki genel piyasa yönünü ve oynaklık sınıfını kaydeder.
  **Yalnızca gerçekten kapatılan sanal işlemler** net kâr-zarar bilgisiyle
  bağlam istatistiklerini günceller. En az 3 sonuçtan sonra küçük bir
  puan düzeltmesi yapabilir; az veri, kesin bir öngörü sağlamaz.
- Haber taraması isteğe bağlı izin gerektirmeyen okuma isteğidir;
  kaynaklar erişilemezse fiyat, koruyucu çıkış ve mevcut kasa çalışmaya
  devam eder. RSS, hızlı işlem sinyali değil, gecikmeli bir risk filtresidir.
- Tüm bilgiler uygulamanın **Otonom Karar Merkezi** bölümünde bulunur.
  Sistem gerçek emir göndermez, gerçek para veya borsa API anahtarı kullanmaz.

## Neden bazen işlem yapmıyor?

Botun amacı işlem sayısını yükseltmek değil, **sanal sermayeyi komisyon
sonrası büyütmeye çalışırken kaybı sınırlamaktır**. Günlük işlem kotası olmadan da yaklaşık %78 toplam pozisyon üst sınırı,
en az %20 nakit rezervi, fiyat tazeliği, teknik teyit ve stop/kâr
koruma şartları nedeniyle BEKLE kararları olabilir.
Kasa dolduğunda yalnızca doğrulanmış olumsuz momentum koşullarında
kontrollü risk azaltımı yapılır. Hiçbir sonuç veya kâr garantisi yoktur.

## Tarayıcı kapalıyken çalışması

- GitHub Actions kron'u yaklaşık 5 dakikalık yedektir; GitHub planlı
  tetiklemeleri geciktirebilir veya atlayabilir.
- Cloudflare Worker yapılandırması **2 dakikada bir** GitHub `workflow_dispatch`
  çağırır. 23 Kasım 2026'da birbirini izleyen 2 dakikalık başarılı
  çalışmaları gözlemlendi; bu anlık/tick düzeyinde işlem veya kesintisiz
  7/24 hizmet garantisi değildir.
- Durumu izle:
  https://github.com/ashina61/sanal-trader/actions/workflows/paper-bot.yml
- Groq gerçek bağlantı deneyi hiçbir sanal emir açmadan:
  https://github.com/ashina61/sanal-trader/actions/workflows/ai-health.yml
- **`reset` kullanma:** Mevcut sanal kasa ve geçmiş işlemleri sıfırlar.

## Kodu ve güncellemeleri izleme

`backend/paper_bot.py` — tek sanal motor; tüm kısa listeye 1dk/15dk grafik,
emir öncesi ikinci güncel fiyat kontrolü ve risk/ivme ağırlıklı aday sıralaması,
`backend/ai_brain.py` — kısıtlı Groq kararı,
`lib/screens/home_screen.dart` — tek sunucu arayüzü,
`assets/changelog.json` — uygulamanın Güncelleme Geçmişi.

Uygulamanın eski tarayıcı demo modülleri ve artık kullanılmayan
Firebase, yerel depolama, manuel emir ve yerel öğrenme testleri silindi.
Sanal botun `bot-data` dalındaki geçmişi, açık pozisyonları ve bakiyesi
**korundu**.

**Yatırım tavsiyesi değildir.** Veri kaynakları, sanal komisyonlar ve
otomatik çalıştırma gerçek ticaretin tüm risk ve maliyetlerini yansıtmaz.
