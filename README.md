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

## Sinyaller doğru mu? (v0.9.15, araştırma katmanı)

- **Canlı ileri doğrulama:** Risk motorunun onayladığı adaylar, gerçek işlem
  oluşturulmadan o andaki kamu spot fiyatıyla işaretlenir. En fazla 3 aday
  döngü başına kaydedilir; aynı yön/coin için bir saat boyunca tekrar örnek
  alınmaz. Bir saat sonra **gerçekten görülen** fiyat varsa sonuç hesaplanır.
  Fiyat 20 dakika daha gelmezse örnek sonuçsuz kapanır, kâr icat edilmez.
- Bir saatin sonunda SPOT AL veya 1x referans SHORT yönüne göre fiyat farkı
  hesaplanır. Sonuçtan toplam **%0,2 varsayımsal komisyon ve %0,1 varsayımsal
  kayma (toplam %0,3)** düşülür. Bu **gerçek emir, ikinci kasa, gerçek
  likidite ya da garanti edilen işlem fiyatı değildir**.
- Bot Karar Merkezi **bekleyen / ölçülen sinyaller**, ortalama komisyon
  sonrası getiri ve isabet oranını gösterir. Bir yönde ve rejimde en az
  **30 tamamlanmış gerçek gözlem** yoksa sonuç karar puanına etki etmez.
  Sonrasında en fazla ±0,04 puan ile yalnızca daha önce risk onayı almış
  adayların sırasını etkiler; zararı durdurma ve diğer korumaları aşamaz.
- **Tarihsel walk-forward:** Ayrı Python çalışması Binance'in gerçekten
  kapanmış 15 dakikalık mumlarını alır, BTC ve seçilmiş coinleri zamanla
  eşleştirir; en erken %70 veriyi geliştirme, son %30'u dokunulmamış
  değerlendirme bölümü olarak kullanır. Her karar yalnız o ana kadarki
  mumlardan verilir; ileri 1 saatlik fiyat sadece sonucu ölçer.
- Bu tarihsel ölçüm **canlı stratejinin aynısı değildir**. Saatlik+15dk
  giriş vekili kullanır, 1dk teyidi / haber / Groq / gerçek spread / emir
  defteri / SHORT borçlanma maliyetlerini kapsamaz. Güncel listelenen
  coinleri seçtiği için hayatta kalma yanlılığı da vardır.
- Her gün ücretsiz GitHub Actions üzerinde ayrı rapor denenir ve sonuç
  **Actions artifact** olarak saklanır; bot-data kasasına veya işlem
  geçmişine karışmaz. Kamu verisi kullanılamazsa rapor çıkarılamadığını
  açıkça bildirir. İşlem botu tarayıcı kapalıyken aynen çalışır.
- Araştırma komutu:
  `python3 -m backend.walk_forward --symbols BTCUSDT ETHUSDT SOLUSDT --out validation-report.json`

## Öğrenen çıkışlar ve yanlış sinyal kontrolü (v0.9.16)

- Piyasa yukarı yönlü ve taranan en az 12 coinin %70'i yükseliyorsa,
  **yeni SHORT** açılmaz. Yalnızca gerçekten kapanmış piyasa mumları ve
  BTC yönü kullanılır. Daha önce açılmış SHORT emirleri otomatik kapatılmaz:
  kendi 15dk+1dk mumları da yükseliş dönüşünü onaylamalı, pozisyon
  en az 45 dakika taşınmış ve aleyhte en az %0,6 hareket görülmelidir.
  Stop/kâr koruması bunlardan bağımsız önceliklidir.
- Zayıflayan **SPOT** için en az 2 saat bekledikten, düşük fakat anlamlı
  zarar oluştuktan ve saatlik+15dk+1dk düşüş teyidinden sonra savunma
  amaçlı satış yapılabilir. Her düşüşte hemen SAT veya sırf başka coin
  almak için zararına rotasyon yapılmaz.
- Gerçekte zarar ile kapanan bir coinde 90 dakika boyunca **yeni giriş**
  ertelenir. Kârla kapanan coinlere bu ek kısıt uygulanmaz. Koruyucu
  kapanışlar asla bekleme kuralına takılmaz.
- Doğrulanmamış SHORT 1x sanal işlem büyüklüğü normal SPOT miktarının
  %75'i kadardır; geriye dönük alınmış son 6 gerçek ileri SHORT sinyali
  tamamı zarar gösterirse %50'ye kadar iner. Bu bir kâr tahmini değildir
  ve sınır küçük örneklemde koruma amaçlıdır.
- **Cüzdan dolsa da öğrenme:** Aynı piyasa verisinden ve aynı teknik
  filtrelerden sanal emir vermeyen araştırma adayları hesaplanır.
  Gerçekten gözlenen bir saat sonraki fiyata bakılır. İkinci kasa,
  kurgusal işlem emri, geçmiş veride gelecekten yararlanma yoktur.
  Koruyucu çıkışlar gerçek cüzdanda aynı şekilde öncelikli kalır.
- Uygulamanın açık pozisyonlar alanında komisyon sonrası yaklaşık
  kapanış net değeri, tutulma süresi ve coin görünür. Gözlem ekranı
  işlem yaptırmaz; maliyet ve eski veri nedeniyle değer değişebilir.
- **Önemli:** Botun zarardan çıkması garanti değildir. Bu sürüm zarar
  kaynağını ölçüp disiplini arttırmaya yöneliktir; eski 650 TL
  başlangıçlı kasa, 9 açık pozisyon ve tüm geçmiş işlemler korunur.

## Hızlı tarama ve ölçülen olumsuz sinyali frenleme (v0.9.17)

- **Grafik gecikmesi:** Yeni, ücretsiz ve sınırlandırılmış eşzamanlı okuma, en fazla
  6 adet bağımsız Binance kamu verisi isteğini birlikte çalıştırır. Saatlik,
  15dk ve 1dk mumları yine gerçek kapanmış verilerden oluşturur; kasa ve
  emir yönetimi eşzamanlı değildir ve **tek cüzdanda** kalır. API eksikse
  veri uydurulmaz; eski 1dk teyidi otomatik kullanılmaz.
- **Hız ölçümü:** Bot karar ekranında mum API istekleri, veri tarama saniyesi
  ve iş parçacığı sayısı gösterilir. Bu yalnız grafik isteği süresidir;
  GitHub Actions başlatma/deploy gecikmesi ve Groq süresi dahil değildir.
  İşlem döngüsü hâlâ ücretsiz Cloudflare tetiklemesiyle yaklaşık **2 dk**
  aralıklıdır. Tick düzeyinde veya 7/24 kesintisiz hız garantisi yoktur.
- **Gözlemlenmiş zarar freni:** Son 12 ileriye dönük SPOT sinyali ortalama
  net getirisi en fazla -%0,30 ve başarılı oranı en fazla %35 ise yeni
  SPOT girişlerine ara verilir. SHORT için son en az 6 sinyal ortalama
  -%0,45 veya kötü ve başarı oranı en fazla %34 ise yeni SHORT açılmaz.
  Bunlar istatistiksel kârlılık kanıtı değil, küçük örneklemde temkinli
  **yeni giriş sınırlamalarıdır**.
- Koruyucu SPOT SAT / SHORT KAPAT daima çalışır. Mevcut açık pozisyonlar
  korunur, geçmiş P&L resetlenmez. Girişler ancak sonraki gerçek piyasa
  gözlemleri yuvarlanan son 12 örneğin risk durumunu iyileştirirse
  otomatik tekrar değerlendirilebilir.
- **Öğrenme devam eder:** Yeni emir verilmese bile aynı gerçek fiyatlarla
  araştırma sinyalleri toplanır; bir saat sonra fiyat görülürse ölçülür.
  İkinci hayali kasa yaratılmaz. Groq onaylarının araştırma etiketleri
  canlı seçilen simge ve yöne göre kaydedilir.
- Bu değişiklik doğrudan kâr üretmez. Önce gecikmenin düştüğü,
  sonra güvenilir yeni verilerde net sonuçların iyileştiği doğrulanmalıdır.

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
