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

## Kaç parite izleniyor? (v0.9.21)

Bot taze fiyatı olan, hariç tutulan stable/kaldıraçlı sembollere girmeyen ve
24s hacmi en az 1.000.000 USDT olan **tüm düz USDT paritelerini** fiyat/hacim
evrenine alır. Önceki sabit yaklaşık 51 grafiklik kısa liste kaldırıldı.
Gerçek parite sayısı piyasaya göre değişir; tüm kotasyon sayısı coin sayısı değildir.

1dk grafiklerde normal döngü sınırı 96 paritedir. Açık pozisyonlar, çekirdekler,
hacim liderleri ve hareketli adaylar öncelikli; kalanlar kalıcı imleçle sırayla
incelenir. Saatlik/15dk önbellek sırasıyla en fazla 72/96 yeni sorguyla hazırlanır.
İlk genişlemede veri birkaç döngüde tamamlanabilir. Eksik/başarısız veri onay
sayılmaz. Likidite filtresi dışındaki açık pozisyonun fiyat kontrolü sürer.

Kasa ve Bot ekranlarında likit parite, başarılı 1dk grafik, son 10dk benzersiz
kapsam ve üç zaman dilimi hazır sayıları görünür. Bot ekranındaki açılır listede
izlenen semboller bulunur. Son kapsam zaman damgasıyla gösterilir; tekrar tetik
atlandığında eski kapsam yeni tarama gibi gösterilmez.

API 429/418 verdiğinde bekleme süresi saklanıp sonraki süreçlerde de korunur.
Grafik okuması yaklaşık 45s bütçeye tabidir; ana fiyat yenilemesi bu grafik
bütçesinden bağımsızdır. Bu, ağ veya tüm döngü süre garantisi değildir.
Daha geniş tarama net kârlılığı tek başına kanıtlamaz; strateji ve kasa sonucu
ayrı ölçülür. Tek kasa, mevcut risk ve masraf koşulları korunur.

## Net kasa büyümesi ve strateji değerlendirmesi (v0.9.20)

Ana değer, gözlenen fiyatlardan hesaplanan **tahmini kapanış komisyonu sonrası
net tasfiye değeri**dir. Önceden ödenmiş ücretler tekrar düşülmez. Tek kasa ve
geçmiş korunur; yeni net grafik eski brüt noktaları yeniden yazmaz.

SPOT trend/kırılım ve SHORT girişlerinin bir saatlik gözlem sonuçları ayrı
izlenir. Yeterli örnekte aynı giriş türü ve rejim için son gözlemler kullanılır;
az örnekte yön geneline geri dönülür. SHORT ayrıca genel yön frenini korur.
Bu, kötü giriş türlerini bekleten temkinli bir kuraldır; istatistiksel kâr kanıtı
veya geçmişe bakarak garanti verilen bir strateji seçimi değildir.

`python3 -m backend.strategy_replay --out strategy-comparison.json` dört sabit
politikayı aynı altı coin ve aynı kronolojik dönemde karşılaştırır. 15dk kapanış
ve en fazla 4 saat gözlem modeli, %0,3 varsayımsal toplam ücret/kayma içerir.
Gelecek veri giriş koşullarına girmez; eksik mumlar tamamlanmış sayılmaz.
Üretimin 1dk/AI/haber/gerçek likidite akışını yeniden üretmez. İkinci kasa,
kurgusal katlanan sermaye veya otomatik strateji değişimi oluşturmaz.
İlk raporda yeterli olumlu geliştirme sonucu yoktur. Yeni adaylar için yeni
ileri gözlemler gerekir. Araştırma mevcut ücretsiz günlük akışta saklanır.

## Bot durumu ve çıkış önceliği (v0.9.19)

Kasa ve Bot ekranlarındaki **Botun durumu**, aynı sunucu kasasının son kontrolünü
ayrı alanlarda gösterir: fiyat gözlem saati, borsanın en eski fiyat zamanı,
kontrol süresi, kısa liste, mum sorgularının başarılı/eksik sayısı ve çıkış denetimi.
Tekrar tetik, eksik veri, hata veya gecikme başarılı yeni tarama gibi gösterilmez.

Her döngü önce güncel fiyatlarla **tüm fiyat temelli koruyucu çıkışları** kontrol eder.
Stop, kâr al ve gözlenen zirve/dip koruması tetiklenirse grafik/RSS/AI sorgusu
beklenmeden aynı gözlemde birden fazla pozisyon sırayla kapanabilir. O döngüde
ilave giriş yapılmaz; araştırma sonraki kontrolde sürer. Başka pozisyonun fiyatının
eksik olması, fiyatı doğrulanan pozisyonun stopunu engellemez. Kalan eksiklik
hata olarak işaretlenir; fiyatı olmayan pozisyon için değer veya satış uydurulmaz.

Canlı motor fiyatı yanıtı aldığı saate göre doğrular (en fazla 90 saniye eski,
en fazla 5 saniye ileri). Geniş grafik sorgularından sonra yeni fiyat alır.
Yeni teknik onayda son kapanmış 1dk/15dk/1s mum sırasıyla en fazla
180/1800/7200 saniye eski olabilir. Mevcut kuralların stop/kar-al eşikleri değişmez.

Bu **periyodik REST** altyapısıdır; kesintisiz WebSocket takibi veya aradaki
fiyatlardan garantili stop gerçekleşmesi iddiası yoktur. Tek kasa ve geçmiş korunur.

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

## Neden üç saattir işlem yok? İşlem şeridi ve çıkış incelemesi (v0.9.18)

- 23 Kasım öğleye doğru canlı bot-data kasasında **30 geçmiş sanal emir**
  vardı: 18 SPOT AL, 8 SPOT SAT, 2 SHORT AÇ, 2 SHORT KAPAT.
  Son yeni emir saat 06:44 UTC civarında gerçekleşmişti. Bot çalışmayı
  sürdürüyordu; sadece artık uygun giriş bulamamıştı.
- O andaki kasa 650 TL başlangıca karşı **yaklaşık 637 TL**, 10 SPOT
  pozisyonu açık, nakit ~141 TL; sermayenin yaklaşık %78'i açıktaydı.
  Piyasa 1dk/15dk teyidi yetersiz gördüğünde emir verilmez.
- **Ana ekran ve Bot ekranı** şimdi son 4 gerçek sanal emri doğrudan
  gösterir: SPOT AL/SAT, SHORT AÇ/KAPAT, coin adı, işlem tutarı
  veya satışın gerçekten kapanmış net kâr/zararı. Geçmişte
  gerçekleşmeyen sanal işlem uydurulmaz.
- Ana ekranda **son emir saati**, açık pozisyon yüzdesi ve son
  BEKLE kararının gerçek nedeni de görünür. Bot kartında incelenen
  açık pozisyon sayısı ve koruyucu çıkış adayı sayısı gösterilir.
  Tüm işlemler ayrı **İşlemler** sayfasında kalıcıdır.
- Yeni **spot kâr koruma** kuralı, yalnızca geçmişte gerçekten
  gözlenen zirve maliyetin en az %1,2 üzerine çıkmışsa, emir en az
  45 dakikadır açıksa, güncel fiyat zirveden en az %0,45 düşmüşse,
  pozisyon maliyeti üzerinde en az %0,65 kalıyorsa ve gerçek 1dk
  mumları tersine dönüşü doğruluyorsa koruyucu SPOT SAT planlar.
  Çıkış komisyonu sonrası hâlâ pozitif kâr şartı gözetilir;
  teyitsiz sinyaller satış üretmez.
- Bu bir **kâr garantisi veya işlemi artırma kotası değildir**.
  Bot sırf kullanıcı daha çok işlem görmek istiyor diye para
  kaybettiren al-sat döngüsüne zorlanmaz. Sürekli piyasa taraması
  ve doğrulanmış stoplar önceki gibi sürer.
- 650 TL başlangıçlı **tek sanal kasa**, 30 geçmiş işlem,
  nakit ve açık pozisyonlar sıfırlanmaz; gerçek para kullanılmaz.

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

## Akıllı Para Radarı (v0.9.22)

Radar ekranında Solana/Base akıllı cüzdan araştırma alanı vardır. En fazla 15
uygun kârlı cüzdanda, 20 dakika içinde üç **bağımsız** alım, fon girişinin
teyidi, token likiditesi/kontrat güvenliği ve fiyat şişmesi kuralları uygulanır.
Hatalı, eksik, gecikmiş veri geçerli sinyal sayılmaz. İşlem kimlikleri,
satış uyarıları ve son 24 saatlik sinyal kaydı tek sunucu durumuna eklenir.

**Veri kaynağı olmadan aktif izleme yoktur.** Güvenilir on-chain indeksleyicinin
HTTPS JSON adresi için GitHub Actions `SMART_WALLET_FEED_URL` secret gerekir.
Bu modül sunulan kanıtları bağımsız zincir üzerinden yeniden doğrulamaz. DEX
fiyat ve gerçekçi dolum olmadan yeni sanal emir açmaz, hiçbir gerçek alım/satım
yapmaz ve ana 650 TL sanal kasayı değiştirmez. Ayrıntılı veri şeması ve
kısıtlar: [Smart Money bağlantı rehberi](docs/smart-money-feed.md).

## Ücretsiz DEX keşfi (v0.9.23)

Solana ve Base için ücretsiz, API anahtarsız GeckoTerminal havuz/işlem
örneklemesi eklendi. Github Actions sunucu botu çalıştığında son 12 dakika
içinde tarama yapılmamışsa her ağdan en fazla iki havuzu inceler, işlem
gönderen adresleri 20 dakikalık pencerede sayar ve üç farklı adresin aynı
tokeni almasını doğrulanmamış araştırma gözlemi olarak gösterir.

Bu adresler kanıtlanmış başarılı akıllı cüzdanlar değildir; herkese açık
işlem örneklemesi cüzdanın 30 günlük kârını, bağımsız sahibini, fonun kaynağını
ve token LP/mint/blacklist güvenliğini doğrulamaz. Önceki SMART_WALLET_FEED_URL
ile yalnızca doğrulanmış sağlayıcı beslemesi kabul eden katman ayrı durur.
Ücretsiz veri bulunmazsa hata görünür; veri uydurulmaz. Hiçbir DEX işlemi
veya ayrı kasa oluşturulmaz.

Kurallar ve sınırlar: [Ücretsiz DEX Radar rehberi](docs/free-dex-radar.md).

## Altı aşamalı karar denetimi + kompakt mobil UI (v0.9.24)

Tek sunucu kasasında her yeni BUY/SHORT adayı için seçici Binance public
emir defteri denetimi uygulanır: PULSE/IMPACT/EDGE/SIZE/ENTRY.
EXIT, her zaman önce çalışan mevcut koruyucu satış/kapama mekanizmasıdır.
Bu bir otomatik fiyat tahmin modeli veya gerçek emir yollayan 6 ayrı AI ajanı
değildir. Sadece görünür emir derinliği ve işlem maliyetinin engelleyici
sinyalleri kullanılır. Veri yoksa yeni risk engellenir; mevcut pozisyonlar
ve önceki zarar/kâr kayıtları korunur.

Kasa, Radar, Bot ve Kâr sayfaları önce temel bilgiyi gösterir;
gelişmiş tanılar açılır. Kâr sayfasında büyük kasa özeti yinelenmez.
[Karar aşamaları ve mobil düzen ayrıntıları](docs/decision-pipeline-compact-ui.md).

## Denetim düzeltmeleri (v0.9.25)

Emir defteri kaynağı hiç mevcut değilse bile yeni BUY/SHORT kararı onay
alamaz. Sağlayıcı testi de geçerli derinlik verisi vermelidir. Satış ve
koruyucu SHORT kapatma önceliği korunur. Ücretsiz GeckoTerminal istekleri
artık rate-limit riskini düşürmek için 6 saniye arayla yapılır ve kaynak
HTTP hata kodları açıkça görünür; veri çalışmazsa sinyal üretilmez.
Manuel kasa sıfırlama seçeneği GitHub Actions/CLI menüsünden çıkarıldı.
Botun tek sanal kasası ve geçmişi korunur. Bu değişiklikler kâr
garantisi veya devamlı WebSocket takibi sağlamaz.

### Kripto dışı tokenize menkul kıymet filtresi

Resmî Binance duyurusunda bStocks sınıfında bulunan tokenler (örn.
CRCLB, INTCB, METAB, SPCXB, NVDAB, AAPLB) yeni kripto stratejisi
pozisyonuna alınmaz. Mevcut kasa bunlardan pozisyon tutuyorsa satılacak
fiyatları alınmaya ve stop/koruyucu çıkışlar çalışmaya devam eder.
Bu sadece bilinen semboller için denetlenmiş bir sınıflandırma listesidir;
yeni listelenen tokenize menkul kıymetleri otomatik tanımaz.
Kaynak: https://www.binance.com/en/support/announcement/detail/4fea39f8b6e54e1b88e388fc90ce323e

## DEX rug araştırması ve kapalı işlem öğrenimi (v0.9.26)

Mevcut Solana/Base ücretsiz DEX keşfine en fazla dört token için GoPlus
Token Security kamu veri kaynağı eklendi. Alanlar bulunamıyorsa güvenlik
bilinmiyor gösterilir; bu **akıllı cüzdan onayı veya ticaret izni değildir**.
LP kilidi veya gerçekleşebilen satış garantisi yoktur, DEX otomatik
işlemleri kapalıdır.

Binance public depth20 tutarı tam USDT bütçesine göre hesaplanır.
Mevcut sanal kasa rakamının yanına yalnızca ayrı bir 5 baz puan ekstra
çıkış kayması **stres senaryosu** eklenir, geçmiş kasaya dokunulmaz.
Bot/Kâr arayüzünde kapanan sanal işlemlerden net rapor ve kayıp serisi
görülür. Otomatik yeni strateji veya kâr garanti edilmez.
[Detaylar](docs/rug-cost-learning-v0926.md).
