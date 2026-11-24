## 2026-11-24 — v0.9.33 Net kârlılık avantajı olmadan yeni sanal giriş yok

- Gerçek mevcut tek sanal kasanın son erişilen fiyat gözlemi 640,20 TL; başlangıç 650 TL. 181 ileriye dönük 1 saatlik sinyal sonucunda ortalama varsayımsal **-%0,335 net** görüldü. Kod/test başarısı para kazanma kanıtı değildir.
- Yeni salt-okunur **ekonomik kârlılık hazır olma** denetimi her yön için ayrı uygulanır. Yön bazında 30+ tamamlanmış ileri fiyat gözlemi olduktan sonra yeni sanal SPOT BUY / 1x SHORT riskine, en az 60 tamamlanmış sonuç, son 60'ta +%0,15 net ortalama, son 24'te +%0,20 net ortalama ve en az 14 pozitif, en az 8 farklı coin ve en son 3 saatte gözlenmiş yeni ölçüm birlikte yoksa izin verilmez. Bu göstergeler kârı garanti etmez; yalnızca yeni giriş veto koşuludur.
- SHORT'un son 24 gözlemi geçici olumlu olsa bile son 60 negatifse bot yeni risk açmaz. Pozisyonların var olan SPOT SAT / SHORT COVER / STOP koruması ve araştırma modu çalışır. Emir geçmişi, tek kasa, fiyat kaynakları ve gerçek emir olmaması korunur.
- Bot sayfasında SPOT/SHORT için 'Net kâr avantajı doğrulanmadı' gösterilir. Daha ileri net ölçümler gerektiğinde aynı kontrol tekrar değerlendirilir. Sürüm 0.9.33+39.

## 2026-11-24 — v0.9.32 Kasa mutabakatı ve tekrarlı çalışma koruması

- Aynı GitHub çalışma kimliğinin gecikmiş tekrarı ikinci karar üretmez; son 2048 kimlik saklanır.
- Son 288 çevrimin sürümü, tetikleyicisi, sonucu ve ret nedenleri kaydedilir.
- Nakit ve açık pozisyon maliyetleri başlangıç kasa ile gerçekleşmiş sonuçla karşılaştırılır. Uyuşmazlık yeni riski durdurur; koruyucu çıkışlar önceliklidir.
- İşlem istatistiklerinin son 100 emir kaydı kapsamı belirtilir. Mevcut kasa korunur; kâr garantisi yoktur.
- 224 backend ve 6 zamanlayıcı testi geçti.

## 2026-11-24 — v0.9.31 Gerçek zarar serisi ve yanlış açılan trend freni düzeltildi

- 24 Kasım 12.24 (Türkiye) ölçülen tek sanal kasanın net değerinin 641,83 TL'ye, 650 TL başlangıçtan -8,17 TL'ye gerilediği doğrulandı. Gerçekleşmiş kapanışların net toplamı -3,52 TL; son iki farklı SPOT zarar kes (NEARUSDT, SPCXBUSDT) yaklaşık 9 dakikada toplam -3,04 TL zarar yazdı. Bu rakamlar gerçek zamanlı piyasa verisine bağlıdır, gün boyu sabit değildir.
- **Kritik mantık hatası düzeltmesi:** SPOT trend'in kapanış sonucu 1/4 -7,65 TL iken 2/6 -9,56 TL'ye düştüğü hâlde, kazanma oranı %25'in üzerine çıktı diye giriş freni kendiliğinden kalkabiliyordu. Artık en az dört kapanış, toplam en az -3 TL ve ortalama net ROI en fazla -%0,75 ise, kazanma sayısının artması tek başına o kaybettiren kurulumun kilidini açamaz. Pozitif net gerçekleşen yeniden değerlendirme veya ayrıca doğrulanmış strateji değişimi gerekir.
- **Seri zarar kes devre kesicisi:** 90 dakika içinde iki **farklı coinde** gözlenen negatif SPOT SAT veya SHORT COVER 'zarar kes' kapanışı toplamda başlangıç kasasının en az %0,3'ünü kaybettirmişse, ikinci zarardan sonraki en çok 120 dakika boyunca **yalnız yeni** sanal BUY/SHORT girişleri duraklatılır. Diğer güvenlik/strateji frenleri değişmez; zaten açık pozisyonların SPOT SAT/SHORT COVER/STOP korumaları en yüksek öncelikte çalışmaya devam eder.
- Araştırma modunda yeni giriş simülasyonu olmadan fiyat adayları ve ileri ölçümler toplanmaya devam eder. Zaman aşımı sonunda bu ek fren yeniden değerlendirilir; otomatik kâr vaadi yoktur. Kasa, açık pozisyonlar, emir kayıtları ve ücretler silinmez/değiştirilmez.
- Bot sayfasında kalan geçici giriş beklemesi ve koruyucu çıkışların çalıştığı gösterilir; Flutter 0.9.31+37. Bağımsız coin/zaman kontrolü, hatalı veri, koruyucu çıkış önceliği, araştırma sürekliliği ve net kayıp regresyon testleri eklendi.

## 2026-11-24 — v0.9.30 Risk bütçesiyle seçici büyük SPOT pozisyon

- 650 TL'lik tek sanal kasadaki kârlı çıkışlar çoğunlukla 20–80 TL tutarındaki girişlerden geliyor. Örneğin son ALLOUSDT çıkışı +0,39 TL. Pozisyon büyüklüğünü genel piyasa koşullarında rastgele artırmak yerine, **yalnız hem tamamlanmış kazanan kapanış hem ileriye dönük net fiyat gözlemi şartını sağlayan YATAY/SPOT/breakout** denemesine ayrı büyüklük modeli eklendi.
- Önceki seçici denemede toplam kasanın %12'sinin yarısı (yaklaşık 39 TL) üst sınırdı. Yeni modelde **en fazla kasanın %18'i**, aynı anda **en fazla üç breakout pozisyonu**, bu pozisyonlara ayrılan **toplam değer en fazla kasanın %25'i**, genel pozisyon payı **en fazla %78** ve serbest nakit rezervi **en az %20** korunur. Bunların en kısıtlayıcı olanı geçerlidir.
- Yeni SPOT breakout girişinin varsayımsal stop riski tüm sanal özsermayenin **en fazla %0,60'ı** ile sınırlandırılmaya çalışılır: gözlenen SPOT stop %2,8, varsayımsal gidiş-dönüş komisyonu %0,2 ve ek kayma %0,1 varsayılır. Bu yalnız **risk senaryosudur**; 5 dakikalık GitHub cron veya gecikmiş anlık fiyat, sert boşluk ya da emir defteri kayması nedeniyle gerçek kayıp hesaplanan bütçeyi aşabilir.
- Normal SPOT trend, SHORT, açığa alım, zarar kes ve mevcut koruyucu çıkış kuralları, haber kontrolü, giriş yönü ve olumsuz ileri sonuç frenleri değiştirilmedi. Sadece gerçekten nitelikli SPOT breakout pilotlarının TL tutarı artabilir; işlem miktarı veya kesin kâr vaat edilmez.
- AI farklı onaylı bir coin seçerse, seçilen coinin kendi kayıtlı tutarı ve risk denetimi kullanılır. Bot ekranında planlanan sanal tutar ve model stop zarar senaryosu görülebilir.
- İlk kasa 650 TL, mevcut sanal emir geçmişi ve tek hesap aynen korunur; gerçek alım satım yapılmaz. Yeni maliyet/konsantrasyon ve AI seçim testleri eklendi. Sürüm 0.9.30+36.

## 2026-11-24 — v0.9.29 Gerçekleşmiş kazanan kurulumu ayıran SPOT denemesi

- Tek sanal kasanın bu sürüm öncesi kapanan, sinyal etiketli SPOT kırılım işlemleri: 8/8 kârlı, toplam +11,45 TL; SPOT trend: 1/4 kârlı, -7,65 TL; SHORT: 0/3 kârlı, -6,80 TL. Bu tarihsel ve seçilmiş örneklem **kârlılık garantisi değildir**, açık pozisyonlar bu karşılaştırmaya dahil değildir.
- Yeni **kâr öncelikli deneme politikası**: sadece YATAY rejimde ve 1dk gerçek breakout sinyalinde, geçmişte en az 6 tamamlanmış SPOT breakout işlemi, >=%75 kazanan, >=+2 TL gerçekleşmiş net ve ortalama en az +%0,75 net ROI varsa değerlendirme sürer. Buna ek, aynı kurulumun son en az 6 daha sonra gözlenmiş 1 saatlik fiyat sonucunda ortalama en az +%0,10 net, en az 3 pozitif, 5 farklı tarama ve 5 farklı coin, en son ölçüm 3 saatten güncel olmalıdır.
- Bu iki bağımsız-kısmen-ilişkili kanıt kümesi olumluysa geniş yönün net negatif giriş frenine **en fazla yarım pozisyon büyüklüğüyle**, aynı anda en fazla iki açık breakout pozisyonu olacak şekilde sınırlı sanal test istisnası mümkün. Mevcut haber, komisyon, emir defteri, teknik teyit, konum, geçmiş ve risk frenleri aşılmaz. Kurulum şartları olumsuza dönerse izne son verilir.
- Son dört kapanan SPOT trendi güçlü net zarar ve düşük kazanma oranındaysa o kurulumda yeni risk bekletilir. Üç SHORT kapanışı 3/3 zararlı olduğundan, yönün ileriye dönük son 24 sinyali belirgin biçimde pozitif iyileşmeden yeni SHORT riski tekrar açılmaz. Koruyucu satış ve SHORT kapama hep önceliklidir.
- Bot/Kâr sayfasındaki öğrenme kartına 'Hangi strateji gerçekten kazandı?' başlıklı kısa, açılır net performans tablosu eklendi. **Tek kasa korunur**, ikinci demo cüzdan veya gerçek emir yok. Sürüm 0.9.29+35.

## 2026-11-24 — v0.9.28 Kârı geri vermeme ve seçici kazanç denemesi

- 650 TL tek sanal kasanın 25 gerçekleşmiş kapanışındaki net kâr yalnızca +0,08 TL; iki SHORT kapanışı yaklaşık -5,17 TL. Ortalama 1 saatlik ileri sinyal getirisi işlem maliyeti sonrası negatiftir. Yeni stratejiler kâr etmiş sayılmaz.
- Koruyucu SPOT zarar kes eşiği gözlenen fiyatta %4,5'ten %2,8'e; sanal 1x SHORT zarar kes eşiği %4,5'ten %2,5'e getirildi. Gap, 2 dakikalık manuel tetik ve seyrek GitHub cron gerçek gerçekleşme garantisi vermez.
- Daha önce GÖZLENEN tepe/dip en az %1,2 elverişli olmuş ve fiyat tepe/dipten en az %0,85 geri dönüp yeniden giriş fiyatına yaklaşmışsa, mevcut SPOT SAT / SHORT COVER muhasebe yoluyla erken koruma değerlendirilir. Fiyat, miktar, geçmiş emir veya kâr uydurulmaz.
- Küresel olumsuz ileri sinyal freni korunur. Buna rağmen sadece YÜKSELİŞ rejimindeki SPOT breakout kurulumunun en az 20 kapanmış 1 saatlik ileri gözlemi varsa, son 12'si ortalama en az +%0,40 net ve en az 7 pozitif; son 6'sı ortalama en az +%0,15 net ve en az 4 pozitif; en az 4 farklı tarama zamanı ve son 4 saatte son tamamlanmış ölçüm şartlarıyla **yarım pozisyon büyüklüğünde** seçici giriş mümkün olur. Eski lane'ler ve SHORT istisnasız engellenir. Mevcut çok aşamalı sinyal, komisyon, emir defteri ve strateji frenleri aşılamaz.
- Bu istisna deneme amaçlıdır; bağımlı gözlem, küçük örneklem ve gelecekte kâr belirsizliği sürer. Araştırma modu, açık pozisyonlar, koruyucu çıkışlar ve sanal kasa geçmişi korunur.
- Yalnızca veriye dayalı stop, kâr geri verme, olağanüstü kayma ve seçici lane senaryoları için regresyon testleri eklendi. Flutter 0.9.28+34.

## 2026-11-24 — v0.9.27 Net zarar freni ve ileri gözlem denetimi

- Canlı sanal kasanın ileriye dönük kaydettiği son 24 gerçek fiyat gözlemi, SPOT BUY ve 1x SHORT için ayrı izlenir. Yeterli 20+ örnekte komisyon/kayma varsayımı sonrası ortalama net getiri %−0,05 veya altındaysa **ve** kazanan örnek oranı %40 veya altındaysa o yönde **yeni** sanal pozisyon bekletilir. İstatistiksel kâr garantisi değildir.
- Bu fren yalnızca yeni risk açılmasına uygulanır. SPOT SAT, SHORT COVER, stop, portföy değeri ve koruyucu erken çıkışlar aynen çalışır. Açık pozisyonlar otomatik tasfiye edilmez.
- Araştırma modundaki doğrulanmış sinyal adayları frenden muaf olmaya devam eder; yeni fiyat gözlemleri ve ileriye dönük ölçümler kaydedildikçe 24 örneklik pencere kayar ve net sonuçlar düzeldiğinde yeni girişler yeniden değerlendirilebilir. Böylece strateji geçmişin kötü sinyallerinde takılıp kalmaz ama körlemesine işlem açmaz.
- Bot ekranında 'Net sonuç freni' bilgisi kompakt gösterilir. Sıfır AI maliyetli analitik kurallarıdır; yeni ücretli veri sağlayıcısı, yeni kasa veya gerçek borsa emri yoktur.
- Testler: negatif SPOT/SHORT, pencere toparlanması, yetersiz/bozuk veri, fiyat bazlı zorunlu satış önceliği ve araştırma adaylarının kesilmemesi. Flutter 0.9.27+33.

## 2026-11-23 — v0.9.26 DEX riskleri, maliyet senaryosu ve net öğrenme

- Ücretsiz GeckoTerminal keşfinde yalnızca gözlenen maksimum dört token için GoPlus kamu Token Security API'sinden sözleşme riskleri araştırılıyor. Honeypot/mint/transfer, EVM vergi ve Solana yetki uyarıları görülebilir; eksik veri UNKNOWN/UNAVAILABLE, hiçbir token güvenli olarak sertifikalandırılmaz.
- Gerçek DEX emri, ayrı sanal kasa, kurgusal cüzdan kârlılığı veya otomatik akıllı cüzdan takibi eklenmedi. Her sonuç araştırma amaçlıdır. Kapanışların koruyucu önceliği korunur.
- Binance public depth20 için tahmini VWAP artık tam işlem USDT bütçesini baz alır; seviyeler boyunca fazla harcama yanılsaması düzeltilir.
- Ana net kasa/değerleme ve mevcut geçmiş değişmeden, tüm açık pozisyonlar için ek 5 baz puan fiyat kayması stres senaryosu ayrı gösterilir. Bu sonuç gerçekleşen fiyat veya kesin maliyet değildir.
- Sadece gerçekleşmiş sanal kapanışlardan net öğrenme raporu: son 10 çıkış, kayıp serisi, stop/kâr al/takip/rotasyon, spot/short ayrımı ve net kâr/zarar faktörü. Zaten ücret dahil net PnL tekrar ücret kesilerek bozulmaz.
- Radar token risk listesi kompakt açılır panel, Bot ve Kâr ayrı kompakt öğrenme kartı. Python ve Flutter testleri eklendi. Sürüm 0.9.26+32.

## 2026-11-23 — v0.9.25 Denetim: güvenli veri kaynağı ve kasa sıfırlama koruması

- Ücretsiz GeckoTerminal veri kaynağı istekleri arasında en az 6 saniye bırakılır; herkese açık altyapıda hız sınırı riskini azaltır. HTTP hata kodu (ör. 429) artık net olarak kaydedilir ve DEX Radar ekranında görünür. Servisin her zaman erişilebilir olacağı iddia edilmez.
- Kamu veri kaynağının depth yöntemini hiç sağlamadığı durumlar, test sağlayıcısı dâhil, yeni sanal BUY/SHORT işlemi için kesin ret oldu. Daha önce testlerde kaynak yoksa planı olduğu gibi geçiren yol kaldırıldı. Sahte piyasa sağlayıcıları açıkça gerçekçi emir defteri örneği sağlamalı.
- Manuel GitHub Actions ve Python CLI akışındaki reset seçeneği kaldırıldı. Duraklat ve sürdür seçenekleri korunur; tek 650 TL başlangıçlı sanal kasanın mevcut 48+ işlem geçmişi yerinde kalır.
- Binance'in resmî duyurusunda belirtilen bStocks tokenize menkul kıymetleri (CRCLB, INTCB, METAB, SPCXB vb.) artık kripto-odaklı yeni giriş adaylarından açık kod listesiyle çıkarıldı; hâlihazırda tutulan pozisyonlar fiyatla izlenir ve koruyucu SAT engellenmez. Yeni listelenebilecek bStocks için liste düzenli güncellenmelidir.
- Mevcut stop/koruyucu SPOT SAT ve SHORT KAPAT önceliği değişmedi. Hiçbir gerçek borsa emri veya yeni portföy oluşturulmadı. Ücretsiz DEX sinyalleri hâlâ doğrulanmış akıllı cüzdan kârını kanıtlamaz.
- Erişilemeyen veri durumları ve eksik emir defteri için regresyon testleri sıkılaştırıldı. Flutter v0.9.25+31.

## 2026-11-23 — v0.9.24 6 aşamalı karar denetimi ve kompakt mobil ekranlar

- Ücretli çoklu ajan servisi yerine tek Python beynine 6 aşamalı saydam emir ön kontrolü eklendi: PULSE (görünür emir baskısı), IMPACT (20 kademe kayma), EDGE (gerçekçi maliyet; geleceğe dair alpha iddiası yok), SIZE (eski risk bütçesi ve defter derinliği), ENTRY (yalnız sanal fiyat), EXIT (mevcut koruyucu çıkış önceliği).
- Yalnızca teknik ve AI denetimlerinden geçmiş nihai sanal BUY/SHORT için ücretsiz Binance public 20 kademeli order book sorgulanır. Boş/çapraz defter, eski fiyat-derinlik uyumsuzluğu, yüksek makas/kayma, yetersiz hacim yeni sanal girişi engeller. API hata verirse gerçek Market yeni risk açmaz; koruyucu çıkışlar beklemez.
- Yeni girişler varsayımsal emir defteri ağırlıklı fiyatı ile kaydedilir; gerçek gerçekleşme, arbitraj veya tahmin garantisi yoktur. Hiçbir gerçek emir gönderilmez. Tek 650 TL sanal kasa, SPOT/SHORT geçmişi ve maliyet modeli korunur.
- Kasa net bakiye ve ana metrikleri tek bakışta gösteren kompakt karta taşındı; pozisyonlar ve sağlık ayrıntıları açılır oldu. Radar teknik aday/DEX/akıllı cüzdanı ayrı açılır bölümlerle özetler. Bot altı aşama ve kısa kararı öne çıkarır, gelişmiş analiz artık varsayılan açık değildir.
- Kâr sayfasında ikinci dev kasa kartı kaldırılıp net P&L, kazanma oranı, ücretler ve risk özeti öne çıkarıldı; grafik ve hesap detayları açılır bölüme taşındı. Ekranlardan hiçbir işlem geçmişi silinmedi.
- Emir defteri geçerlilik/red/çıkış önceliği ve 320 piksel mobil kompakt görünüm için testler eklendi. Uygulama 0.9.24+30.

## 2026-11-23 — v0.9.23 Ücretsiz Solana / Base DEX Keşfi

- Abonelik, Arkham, Grok veya ücretli API anahtarı istemeyen GeckoTerminal herkese açık REST havuz/işlem gözlemi eklendi. Solana ve Base üzerindeki trend havuzlarındaki işlemler örneklenir; her zincirden en fazla iki likit havuz incelenir.
- En az 200.000 USD havuz rezervi, son bir saatte %30 üzeri yükselişi eleme, en az 100 USD işlem bildirimi ve 20 dakikalık zaman penceresi uygulanır. Tekrarlanan işlem kimlikleri ve adresler çift sayılmaz.
- Üç farklı işlem göndericisinin aynı tokeni alması salt-okunur, doğrulanmamış araştırma kümesi üretir. Bu işlem kârlılık kanıtı, üç bağımsız sahibin kanıtı, taze fon girişi, LP kilidi veya sözleşme güvenliği onayı değildir. Bot otomatik DEX pozisyonu açmaz.
- Tarama 12 dakika önbellekle sınırlıdır; ücretsiz uç noktalar hata verirse başaramama/eksik veri açık görünür. Radar'da havuz, işlem, adres ve 24 saatlik örneklem geçmişi tek sunucu kasasında ayrı freeDexRadar alanında izlenir.
- Mevcut 650 TL sanal kasa, SPOT ve SHORT işlem geçmişi, haber/AI risk filtresi ve koruyucu çıkışlar değişmeden korunur. Kesintisiz anlık fiyat akışı, 15 doğrulanmış milyonluk cüzdan veya kâr garantisi iddia edilmez.
- Ücretsiz keşif için yeni otomatik testler eklendi. Verinin limitleri ve kaynağı docs/free-dex-radar.md sayfasında açıklandı.

## 2026-11-23 — v0.9.22 Akıllı Para Radarı (Solana / Base)

- Binance teknik sinyallerinden ayrı, mevcut tek 650 TL sanal kasaya dokunmayan Solana/Base cüzdan araştırma motoru eklendi.
- En fazla 15 cüzdan, raporlanmış 30 günlük 750.000 USD üzeri kâr ve %65+ başarı, 20 dakika içinde 3 bağımsız alım, farklı fon kaynağı, 200.000 USD likidite, LP kilidi, zincire göre mint/freeze/kontrat kontrolleri ve 1 saatte %30 üzeri yükselişi eleme kuralları uygulandı.
- Aynı tokenin tekrar sinyali engellendi; satış uyarıları ve son 24 saatlik kayıtlar Radar kartında gösterildi. Değişiklik geçmişi, sürüm ve testler güncellendi.
- Kaynak verisi için güvenilir harici indeksleyicinin HTTPS beslemesi SMART_WALLET_FEED_URL secret olarak bağlanmalıdır. Şu an veri bağlı değilse sistem açıkça NOT_CONFIGURED gösterir; Arkham/Grok entegrasyonu kurulmuş gibi iddia edilmez.
- Sağlayıcı beyanları modülde yeniden zincir üzerinden kanıtlanmaz. Gerçek/sanal DEX emri yoktur; %7 giriş ve %-7 stop bu sürümde emir olarak uygulanmaz. Mevcut SPOT/SHORT ve tek kasa kayıtları korunur.
- Python ve Flutter regresyon kontrolleri için PR iş akışı eklendi; canlıya geçiş test sonuçlarına bağlıdır.

## 2026-11-23 — v0.9.21 Geniş evren ve gerçek tarama kapsamı

- Önceki son canlı kontrolde 161 likit USDT paritesi vardı; yalnızca 51 parite ayrıntılı grafiğe giriyordu. İzleme artık sabit kısa liste yerine en az 1 milyon USDT 24s hacim eşiğini ve taze fiyat şartını geçen tüm düz USDT paritelerini kapsar. Gerçek sayı piyasaya göre değişir.
- Ana kasada izlenen likit parite sayısı ve son döngüde başarıyla alınan 1dk grafik sayısı görünür. Durum kartı son 10 dakikadaki benzersiz grafik kapsamını ve 1s/15dk/1dk verisi birlikte hazır parite sayısını da gösterir. Ham çoklu işlem çifti kotasyonları coin sayısı gibi sunulmaz.
- 1dk grafikler her döngüde normalde en fazla 96 parite için sorgulanır. Açık pozisyonlar ve çekirdek pariteler önceliklidir; hacim liderleri ve yükselen/düşen adaylardan sonra kalan evren sırayla dolaşılır. Sürekli veya tüm paritelerin her döngüde incelendiği iddia edilmez; başarı yalnız gerçekten alınan veriyle sayılır.
- Saatlik grafik önbelleği döngü başına 72, 15dk grafik önbelleği 96 yeni sorguyla hazırlanır. Açık pozisyonlar ve çekirdek pariteler öncelikli kalır. Yeni paritelerin verisi birkaç kontrolde tamamlanabilir; eksik, eski veya başarısız 1dk verisi yeni giriş onayı sayılmaz.
- Hacmi eşik altına inen açık pozisyon ve bekleyen araştırma sinyallerinin fiyatı yine izlenir; bunlar yeni likit giriş adayı sayılmaz. Koruyucu fiyat çıkışları geniş tarama ve haber/AI beklemeden önce kontrol edilmeye devam eder.
- 429/418 yanıtı geldiğinde Retry-After süresi dikkate alınır; hemen tekrar sorgu gönderilmez. Bekleme bilgisi bot-data kaydına yazılarak sonraki zamanlanmış süreçte de korunur. Görüldüğünde dakika başına API ağırlığı ve grafik bütçe durumu tanılara eklenir.
- İsteğe bağlı grafik sorguları yaklaşık 45 saniyelik tarama bütçesiyle sınırlıdır; sonraki güncel fiyat sorgusu bu grafik bütçesine bağlanmaz. Bekleyen ağ istekleri ve diğer işlemler nedeniyle bu bir tüm döngü süre garantisi değildir. Okuma eşzamanlılığı en fazla altı olarak kalır.
- Daha geniş grafik önbelleği nedeniyle state.json makine için kompakt JSON olarak kaydedilir; kasa, işlemler ve geçmiş silinmez. Bot sayfasında izlenen paritelerin adları açılır listeden incelenebilir.
- Geniş evrene sırayla erişim, açık pozisyon önceliği, gerçek başarılı kapsam sayımı, API beklemesi ve grafik süre bütçesi için yeni testler eklendi. 146 Python testi geçti; Flutter kontrolleri yayın akışında çalışır. Daha çok parite izlemek kâr garantisi değildir. Flutter 0.9.21+27.
- Flutter telefon testinde parite açılır listesinin kart arka planı üzerinde Material yüzeyi gerektirdiği görüldü; liste kendi şeffaf Material yüzeyiyle düzeltildi. Test beklentisi kaldırılmadı.

- Azalan süre bütçesinde açık pozisyonların 1dk grafikleri geride kalmasın diye 1dk okuması geniş önbellek hazırlığının önüne alındı. Seçim önceliği isteklerin başlatılma sırasında da korunur. Ağ isteği sayısı, bütçe nedeniyle ağa çıkmayan sağlayıcı denemelerinden ayrıca sayılır.


## 2026-11-23 — v0.9.20 Net kasa ve strateji bazında giriş değerlendirmesi

- Ana başarı ölçütü tek sanal kasanın tahmini kapanış komisyonları sonrası net tasfiye değeri oldu. Açılış ve geçmiş kapanış komisyonları iki kez düşülmez; açık SPOT ve 1x sanal SHORT aynı mevcut muhasebe modeliyle hesaplanır. Fiyat eksikse yeni net değer uydurulmaz.
- Ana kasa, kâr ekranı ve yeni grafik noktaları net tasfiye değerini kullanır. Önceki brüt fiyat gözlemleri değiştirilmez; yeni net grafik geçmiş brüt noktalarla karıştırılmaz. Kapanış fiyatı, spread veya kayma garanti edilmez.
- Giriş freni artık yön, giriş türü ve piyasa rejimiyle eşleşen son gözlemleri ayırır. En az 12 SPOT örneği varsa aynı tür/rejim kendi sonuçlarıyla değerlendirilir; az örnekte yön geneline geri döner. SHORT yön genelinin zarar frenini de korur. Eşikler değiştirilmedi; olumlu sonuç kâr kanıtı sayılmaz.
- Böylece zayıf trend alımları, iyi sonuç veren başka bir giriş türünün ortalamasıyla gizlenmez. Farklı giriş türünün zararları yeterince ölçülmüş başka bir SPOT türüne otomatik mal edilmez. Koruyucu SAT/KAPAT ve mevcut pozisyonlar bu yeni giriş freninden etkilenmez.
- AI bağlamına net kasa hedefi eklendi. Teknik aday puanı getiri tahmini veya kazanma olasılığı değildir; birkaç kârlı kapanış pozitif beklentinin kanıtı olarak yorumlanmamalıdır. AI yine yalnızca motorun onayladığı adayları seçebilir.
- Yeni araştırma dört sabit politikayı karşılaştırır: SPOT trend, SPOT kırılım, SPOT geri çekilme sonrası toparlanma ve SHORT kırılım. Altı coin aynı gerçek kapanmış 15dk mumları, aynı kronolojik %70 geliştirme/%30 değerlendirme bölümü ve aynı 4 saate kadar gözlenen kapanış modeliyle incelenir.
- Karşılaştırma toplam %0,3 varsayımsal komisyon/kayma içerir. Eksik mumda durur, gelecekteki fiyat girişe sızmaz, bölüm sınırını aşan geliştirme sonuçları ayrılır. İkinci kasa, portföy katlama hesabı veya otomatik kazanan strateji terfisi oluşturulmaz. 1dk/AI/haber/gerçek emir defteri ve borçlanma şartları bu araştırma vekilinde yoktur.
- İlk gerçek altı coinlik araştırmada dört politikanın hiçbiri yeterli olumlu geliştirme sonucu vermedi; birçok değerlendirme örneği 30dan azdı. Bu sonuçlar kazandıran strateji bulundu şeklinde sunulmaz. Günlük mevcut ücretsiz araştırma akışı yeni karşılaştırmayı raporlar ve artifact olarak saklar.
- Bot ekranında giriş türlerinin gözlem sayısı, ortalama varsayımsal net sonucu ve giriş freni görünür. Yeni ileri sinyaller motor sürümünü taşır; geçmiş veriler karıştırılıp yeniden yazılmaz.
- Mevcut 650 TL başlangıçlı tek sanal kasa, açık pozisyonlar ve geçmiş işlemler korunur. Yeni ücretli servis veya gerçek emir yoktur. 137 Python ve 6 zamanlayıcı testi geçti; web kontrolleri yayında ayrıca çalışır. Flutter 0.9.20+26.

## 2026-11-23 — v0.9.19 Bot durumu ve öncelikli koruyucu çıkış

- Kasa ve Bot ekranlarına aynı sunucu kaydından beslenen Botun Durumu alanı eklendi. Başarılı kontrol, fırsat bekleme, kısmi mum verisi, hata, duraklama ve atlanan tekrar tetik ayrı gösterilir.
- Son fiyat gözlemi ile borsanın fiyat zamanı ayrıldı. Döngü süresi, likit evren, kısa liste, fiyatı kontrol edilen pozisyonlar ve gerçekleşen koruyucu çıkış sayısı kaydedilir. Panel yenileme hatası eski kasanın güncelmiş gibi sunulmasını engeller.
- Fiyatla çalışan mevcut stop, kâr al ve gözlenen tepe/dip korumaları, geniş mum taraması, RSS ve AI beklenmeden kontrol edilir. Aynı gözlemde birden fazla SPOT veya 1x sanal SHORT çıkışı varsa tek kasada sırayla kapatılır. Bu döngü yeni pozisyon açmaz; geniş araştırma sonraki kontrole bırakılır.
- Başka bir açık pozisyonun fiyatı eksik olsa da güncel fiyatı olan pozisyonun koruyucu çıkışı engellenmez. Kapanan işlemler korunur; kalan fiyat eksikliği açık hata olarak kaydedilir. Eksik fiyatla yeni işlem veya uydurma toplam değer oluşturulmaz.
- Canlı motor her fiyat yanıtını yanıt alındığı zamana göre doğrular; 90 saniyeden eski veya 5 saniyeden fazla gelecek zamanlı fiyatı kullanmaz. Geniş grafik taramasından sonra fiyatlar tekrar alınır. Son kapanmış mumu aşırı eski olan grafik, yeni teknik onay sayılmaz.
- Teknik çıkış kararı da haber sorgusunu beklemez. Yeniden fiyat kontrolünde çıkış koşulu kaybolursa o karar yeni girişe çevrilmez. Alım, satım, SHORT açma ve kapatma aynı muhasebe yolunu kullanır.
- Veri tazeliği, çoklu koruyucu çıkış, eksik pozisyon fiyatında sağlam kalan stop, tekrar tetik ve küçük telefon ekranı için regresyon kapsamı eklendi. Bot periyodik GitHub Actions altyapısındadır; bu sürüm sürekli WebSocket bağlantısı kurmaz.
- Mevcut 650 TL başlangıçlı tek sanal kasa, geçmiş zarar/kâr, açık pozisyonlar ve işlem geçmişi sıfırlanmaz. Gerçek borsa emri veya yeni ücretli hizmet yoktur. Flutter 0.9.19+25.
- Canlı yayın kontrolünde eski uygulama JavaScript dosyasının önbellekten gelmesi görüldü. Web paketlemesi artık ana kod ve yükleyici için içeriğe göre değişen dosya adları üretir; yeni sayfa eski arayüz dosyasını kullanmaz. Orijinal dosyalar uyumluluk için korunur, paketleme girdileri doğrulanır.


## 2026-11-23 — v0.9.18 Gerçek işlem şeridi, BEKLE açıklaması, zirveden kâr koruma

- Gerçek veri denetimi: 30 sanal emir (18 AL, 8 SAT, 2 SHORT, 2 COVER) gerçekleşmişti ancak son emrin üzerinden yaklaşık 3 saat geçmişti. Portföy 10 SPOT coinle ~%78 dolu, 650 TL başlangıca karşı ~637 TL idi. Botun piyasa kontrolleri çalışıyordu; yeni emir çıkmamasının ana nedeni onaylı sinyal bulunamaması ve dolu portföydü.
- Ana Sanal Kasa paneli ve Otonom Bot sayfasında son dört **gerçek** AL/SAT/SHORT/KAPAT işlemi doğrudan görünür hale getirildi. Yön, coin, işlem tutarı veya gerçekleşmiş net satış sonucu gösterilir; ikinci cüzdan veya sahte işlem yoktur.
- Ana sayfa son emir saati, açık sermaye oranı ve gerçek BEKLE gerekçesini gösterir. Bot kartı kaç pozisyonun koruyucu çıkış açısından incelendiğini ve kaç teknik çıkış adayı bulunduğunu açıklar.
- Yeni koruyucu SPOT satış fonksiyonu, yalnızca gözlenen zirvenin maliyetten ≥%1,2 yüksek, canlı fiyatın maliyet üzerinde ≥%0,65, zirveden çekilmenin ≥%0,45, pozisyon yaşının ≥45dk ve gerçek 1dk mikro hareketinin düşüş teyidi durumunda çalışır. Eski stop/kâr al koşulları ve fee pozitifliği korunur.
- Yeni regresyon testleri: küçük dalgalanmada erken satış olmaması, eksik/pozitif 1dk teyidinde satış olmaması, gözlenen zirve ile 1dk tersine dönüşte gerçek net kârla kapanış, kasa ve işlem geçmişinin korunması.
- Sırf işlem sayısını artırmak amacıyla para kaybettiren emir oluşturulmaz; bu sürüm kâr garantisi vermez. Flutter v0.9.18+24. Tek 650 TL başlangıçlı sanal portföy korunur.

## 2026-11-23 — v0.9.17 Hızlandırılmış grafik tarama, gerçekleşen sonuçlara göre giriş freni

- Ölçülen performans sorunu: GitHub Actions 2 dakikada bir tetiklense de bazı taramalar ~40-75 saniye sürüyordu; bot 50+ coinin kısa süreli mum isteklerini sırayla bekliyordu.
- Yeni backend/scan_engine.py en fazla altı bağımsız Binance kamu grafik isteğini eşzamanlı ve sınırlandırılmış şekilde yapıyor. 1s/15dk/1dk veri sorguları deterministik biçimde birleştirilir; emir/portföy güncellemesi hâlâ tek merkezde sıralı çalışır. API hataları sahte barlara dönüşmez.
- Taramanın gerçek istek sayısı, başarılı/başarısız 1s-15dk-1dk fiyat serisi sayısı ve API grafik tarama süresi state.json + Bot Karar Merkezi'ne işlendi. Veriler CI/GitHub hazırlık ve Groq gecikmesini kapsamaz.
- Gözlemlenen yeni sinyal performansında 21 sonuç ortalama net ~−%0,92, SHORT 7 sonucun 0 kazanan olması nedeniyle yeni giriş riskine kanıta dayalı koruma uygulandı. Son 12 SPOT gözlemi ortalama ≤−%0,30 ve isabet ≤%35 olduğunda SPOT; en az 6 SHORT gözlemi ortalama ≤−%0,45 ve isabet ≤%34 olduğunda yeni SHORT girişleri geçici olarak bekletilir. Bu eşikler kârlılık tahmini değil kayıp azaltma tercihidir.
- Sinyal geçmişi kayar pencereyle yenilenir; emir açılmasa bile salt-okunur araştırma botu fiyat izlemeyi sürdürür ve yeni gözlemler zamanla olumluysa engel otomatik kalkabilir. Koruyucu SAT/COVER işlem onayı bu giriş engeline bağlanmaz.
- Araştırma sinyalinin AI tarafından gerçekten seçilip seçilmediğini ölçmek için gerçek canlı kararın simge ve yönü yalnız gözlem meta verisine eklendi; ikinci kasa veya kurgusal emir yok.
- Regresyon testleri altı paralel işçinin veri okuması, ağ hatasında fail-closed davranışı, zayıf getiride risk freni, olumlu yeni gözlemler sonrası açılması, dolu cüzdanda araştırma ve kasa bütünlüğünü kapsar.
- Başlangıcı 650 TL olan tek sanal portföy, açık pozisyonları, P&L ve işlem geçmişi korunur. Flutter sürümü 0.9.17+23; ücretsiz zamanlayıcının kesin 7/24 çalışması veya kâr garantisi yoktur.

## 2026-11-23 — v0.9.16 Geri bildirimli risk yönetimi ve pozisyon çıkışları

- Canlı sanal cüzdanın 7 SPOT ve 2 SHORT konumunda eksi taşıması sonrası mevcut emir mantığı incelendi. Bu sürüm kâr vaat etmez; yeni risk sınırları ve ölçülebilir çıkış şartları ekler.
- Kısa vadeli SHORT pozisyonu 45 dakikadan uzun açık, en az %0,6 aleyhte, BTC + geniş piyasa yukarı yönde ve pozisyonun 15dk+1dk momentumu da yükselişi doğruluyorsa, sert %4,5 stopa ulaşmadan doğrulanmış ters trend çıkışı planlanabilir. Her zıplamada otomatik panik satışı yapılmaz.
- SPOT uzun pozisyon en az 2 saat açık, −%0,7 veya daha kötü ve 1s/15dk/1dk grafikler aynı yönde ciddi bozulmuşsa aşırı beklemeye karşı kontrollü çıkış adayı olur. Hard stop, tepe/dip izleme, kâr koruma ve teminat limitleri önceliğini korur.
- Yakın zamanda gerçekten zararla kapatılmış coine 90dk boyunca tekrar giriş yapılmaz; kârla kapanışlar etkilenmez ve koruyucu çıkışlara kilit uygulanmaz.
- BTC yükselirken en az 12 likit coinin %70+ kısmı yükseliyorsa yeni SHORT açılmaz. İleri gözlemlerde son 6 SHORT sinyali tümü zararlı ise yeni SHORT büyüklüğü yarıya kadar iner; aksi hâlde yeni SHORT, normal büyüklüğün en fazla %75'iyle açılır.
- Önceki model tam dolu portföyde yeni teknik adayları incelemeden BEKLE döndüğünden öğrenme verisi toplayamıyordu. Aynı gerçek piyasa verisini ve mevcut filtreleri kullanan salt-okunur araştırma taraması artık kasa doluyken de sinyalleri kaydeder. Bu tarama cüzdana emir eklemez veya ikinci portföy oluşturmaz.
- Her açık SPOT/SHORT için gözlenen son fiyatla hesaplanan yaklaşık komisyon sonrası kapanış kâr-zararı ve tutulma saati karar ekranına eklendi; görülmeyen fiyat uydurulmaz.
- Birim testleri: çoklu zaman diliminde teyitli SHORT ters trend, süresi dolan SPOT trend bozulması, sahte/eksik onayla çıkış olmaması, kaybeden coine 90dk yeniden giriş, küçük örneklemden temkinli SHORT miktarı, tam portföyde araştırma adayları, ücret sonrası pozisyon analizi.
- Başlangıçta 650 TL olan tek sanal kasa, mevcut bakiyeler, gerçek sanal kapanışlar ve açık pozisyonlar sıfırlanmadı. Flutter sürümü 0.9.16+22. Gerçek borsa işlemi yoktur.

## 2026-11-23 — v0.9.15 Gözlenen ileri sinyal sonuçları ve kronolojik piyasa testi

- Yeni backend/shadow_validation.py: Ana botun onaylı teknik adaylarının gerçek giriş anı fiyatını ve yönünü ikinci kasa/emir oluşturmadan araştırma kaydına yazar. Bir saat sonraki gözlenen fiyatı ölçer; 20 dakika gecikme dışında fiyat yoksa sinyali sonuçsuz bırakır.
- Doğrulama sonucu SPOT AL veya 1x referans SHORT yönüne göre hesaplanır; varsayımsal toplam %0,3 gidiş-dönüş komisyon/kayma düşülür. Kayıtlar son 360 sonuç ve 180 bekleyen ile sınırlandırılır.
- Aynı coin/yöndeki sinyallerin iki dakikalık cron tekrarları sahte bağımsız veri üretmez. En az 30 gerçekleşen, aynı piyasa rejimi ve yöndeki sinyal kapanışı olmadıkça ileri sonuçların bot aday puanına etkisi sıfırdır; sonrasında da en fazla ±0,04 puanlık bağlayıcı olmayan sıralama farkı oluşturur.
- Groq AI tarafından onaylanan sinyaller ile AI'nin BEKLE dediği teknik adaylar aynı bir saatlik gerçek fiyat metoduyla ayrı izlenir; isabet ve net ortalamaları Bot Karar Merkezi'nde yan yana raporlanır. Bu örneklemler rastgele seçilmediğinden sonuçlar nedensellik veya garantili AI üstünlüğü iddiası değildir.
- Yeni backend/walk_forward.py: Binance'in kapanmış 15dk mumları ve tamamlanmış saatlik grafikleriyle, geleceğe bakmadan saatlik+15dk giriş vekili üzerinde kronolojik %70 geliştirme / %30 ayrı değerlendirme yürütür. Gelecek 1 saatlik fiyatı yalnızca sonucu ölçmek için okur; gappy/yetersiz/verisi eski seri güvenli biçimde reddedilir.
- Günlük ayrı GitHub Actions araştırma iş akışı, internetten gerçek kamu mumlarını kullanarak BTC/ETH/SOL için rapor üretmeye çalışır; JSON'u Actions artifact olarak saklar. Sanal kasa/işlem geçmişi hiç değiştirilmez. Veri kaynağı bozulursa rapor uydurulmaz.
- Canlı 1dk teyidi, haber, AI, emir defteri, gerçek SHORT maliyetleri ve likidite tarihsel vekil teste dahil değildir. Simüle sonuçlar kâr garantisi veya birebir üretim stratejisi doğrulaması değildir.
- Otonom Karar Merkezi'ne ileri sinyal sonuçlarının ölçülen sayısı, bekleyen sayısı, komisyon sonrası ortalama sonucu ve isabet oranı eklendi.
- Yeni Python regresyon testleri: geleceğe bakmama, 60dk vade, yetersiz/güvensiz fiyatın sonuç diye yazılmaması, 30 örnek sınırı, yön karşılaştırması, kronolojik holdout ve ikinci cüzdan oluşmaması.
- Eski sanal 650 TL kasa, açık pozisyonlar, bakiyeler, geçmiş emirler ve haber öğrenmesi korunur. Flutter 0.9.15+21.

## 2026-11-23 — v0.9.14 Haber radarı, piyasayı tanıma ve gerçekleşen işlemlerden öğrenme

- Taranan coinlerin gerçek 24 saatlik değişiminden piyasa genişliği hesaplandı: yükselen, düşen, yatay coin sayısı, medyan değişim, en güçlü/en zayıf adaylar. Bu, gözlemdir; otomatik kâr tahmini değildir.
- CoinDesk ve Cointelegraph ücretsiz RSS kaynakları için backend/news_radar.py eklendi. Kaynak, yayın tarihi, URL/alan adı, makul boyut ve yaş kontrolü var. Yaklaşık 20 dakikalık sunucu önbelleğiyle çalışma yükü sınırlandırıldı.
- Kritik hack/exploit, delist, iflas ve bazı regülasyon başlıkları yalnızca açıkça eşleştirilen coin için en fazla iki saat süreyle yeni girişleri engelleyebilir. Genel uyarı için birden fazla bağımsız kaynak aranır. Haberler otomatik SAT/SHORT açmaz veya koruyucu kapanışları durdurmaz. RSS kesilmesi fiyat analizini engellemez.
- Açılıştaki piyasa rejimi, işlem yönü ve oynaklık sınıfından bağlam anahtarı oluşturulur. Yeni bağlam öğrenimi tamamlanmış sanal işlem net sonuçlarından güncellenir; geçmiş sonuçlar uydurulmaz. Üç gerçek sonuçtan sonra, az örneklem çekmesiyle yalnızca küçük bir aday sıralama etkisi olabilir.
- AI başka teknik adayı seçtiğinde o adayın bağlamı korunur; sistem hatalı sembolün deneyimini başka pozisyona yazmaz.
- Bot Karar Merkezi'ne piyasa genişliği, haber durumu ve son üç başlık ile bağlam öğrenmesi kapanış sayısı eklendi. Bölüm varsayılan olarak kapalı tutulur.
- Birim testleri: güncel RSS / kaynak doğrulama, coin ve genel haber uyarıları, düşük örneklemde öğrenme, kapanan gerçek sonuçlar ve piyasa genişliği. Eski 650 TL sanal kasa, işlem geçmişi ve açık pozisyonlar sıfırlanmadı.
- Uygulama sürümü 0.9.14+20. Bu değişiklikler kâr garantisi değildir ve gerçek borsa emirleri açmaz.

## 2026-11-23 — v0.9.13 Tam grafik kapsamı, kaliteli aday seçimi ve emir öncesi fiyat doğrulaması

- Sunucuda 2 dakikalık Cloudflare tetikleme döngüleri workflow_dispatch ile art arda başarılı çalışırken tek sanal cüzdanın korunması doğrulandı. GitHub Actions / Worker altyapısı milisaniyelik veya kesintisiz 7/24 emir hizmeti değildir.
- Önceden taranan 53 coinin yalnızca 39'unda 1dk, 36'sında 15dk veri bulunabiliyordu. Artık **kısa listeye seçilen her coin** için iki zaman dilimi de alınmaya çalışılıyor; veri gelmezse işlem hâlâ engellenir.
- Onaylı SPOT AL / sanal SHORT adaylarını, eşit saatlik trend puanlarında rastgele sembol adına göre seçmek yerine gerçek 1dk/15dk takip momentumu ve yüksek oynaklığa ceza ile sıralayan kalite puanı eklendi. Seçim kuralı sinyal üretmez veya kâr garantilemez.
- Grafik taramasında geçen süre boyunca eskimiş fiyat üzerinden hayalî emir yazılmasını engellemek amacıyla, bir plan emir verecekse Binance kamu ticker'ı yeniden okunur ve karar güncel fiyatla bir kez daha hesaplanır. Yeni karar uygun değilse **BEKLE** yazılır.
- Karar raporunda toplam pozisyon sınırı etiketi mevcut gerçek %78 sınırıyla eşitlendi; Groq için doğrulanmış üst aday listesi beşten sekize çıkarıldı.
- Tam 1dk/15dk kapsamı, SHORT/spot kalite sıralaması ve eskiyen fiyatla alımdan vazgeçme için yeni Python regresyon testleri eklendi. README iki dakikalık dış tetiklemeyi, mevcut sermaye sınırlarını ve gerçek zamanlı işlem kısıtlarını açıklayacak şekilde düzeltildi.
- Flutter sürümü 0.9.13+19. Mevcut sunucu kasası, açık pozisyonlar, 650 TL başlangıç değeri ve bütün gerçek sanal işlem geçmişi **sıfırlanmadı**.

## 2026-11-23 — Bot kararında gerçek 1dk veri ve öğrenme ilerlemesi

- Bot karar ekranı gerçek 1 dakika mum verisi okunan coin sayısını ve sinyal bazında gerçekleşmiş sanal kapanışları gösterir.
- Henüz açılış sinyali kaydedilmemiş eski pozisyonların satışı öğrenmeye eklenmez; sahte örneklem yaratılmaz.
- Flutter mobil ekran testi bu yeni bilgi alanlarını doğrular.

## 2026-11-23 — İki dakikalık dış zamanlayıcı ve gerçek kısa aralık döngüsü

- Cloudflare Worker yapılandırması `*/2 * * * *` olarak değiştirildi; GitHub botunun 150 saniyelik kısa-aralık deduplikasyonu 75 saniye oldu.
- GitHub'ın beş dakikalık yedek cron'u durur; mevcut tek cüzdan, concurrency ve kısa-aralık deduplikasyonu çakışmayı engeller.
- 60 saniyelik tekrarlı olay atlanır; 125 saniye sonraki gerçek piyasa kontrolü işlenir.
- Yeni Worker deploy'u Cloudflare tarafından uygulanmadan iki dakikalık gerçek servis teyit edilmiş sayılmaz. Bu hâlâ anlık tick işlem altyapısı değildir.
- Mevcut sanal portföy ve kayıp geçmişi değiştirilmedi.

## 2026-11-23 — v0.9.12 Gerçek 1dk karar, kota yerine sinyal, doğrulanmış öğrenme

- Mevcut 650 TL sanal kasanın 4/4 zarar kapanışı ve komisyon kaybı sonrası botun günlük işlem kotası/yapay 60 dakika genel bekleme sınırları kaldırıldı.
- Yeni girişler artık gerçek kapanmış 1 dakikalık / 15 dakikalık / saatlik sinyal ve komisyon güvenliğiyle değerlendirilir; gözlenmeyen fiyatlarda hayalî emir yok.
- Tek coin için 10 dakikalık dönüş filtresi, %78 toplam maruziyet, %20 sanal nakit rezervi, fiyat doğrulaması ve portföy düşüş koruması devam eder. Düşük güvenli sinyalde BEKLE doğrudur.
- 1dk sert düşüş/yükseliş *gözlendiğinde* SPOT veya SHORT riski hızlı sınırlanır; anlık fiyat arasındaki mumların tamamında emir açılmış gibi gösterilmez.
- Açılışta sinyal kurulumu, kapatmada gerçek net sonuç `signalStats` istatistiklerine yazılır. Geçmişten uydurma işlem/etiket üretilmez; düşük örneklemde model ağırlığı yoktur.
- Bot `workflow_dispatch` ile dışarıdan yaklaşık beş dakikada bir çalıştırılmaktadır; bu mimari gerçek zamanlı tick botu değildir.
- Python testleri yeni karar kuralları için güncellendi. Eski sanal portföy ve gerçek geçmiş zararlar aynen korunur.

## 2026-11-23 — Komisyon hassasiyeti regresyon test düzeltmesi

- Testte ret nedeni sözlüğünün anahtarına kısmi eşleşme yerine gerçek tam etiketle bakılıyor. Koruyucu işlem kuralı değiştirilmedi.

## 2026-11-23 — v0.9.11 Komisyon sonrası kazanç için işlem kalitesine dönüş

- Son canlı sanal kasa denetiminde: 16 sanal işlem, 4 zararlı kapanış, -1,91 TL gerçekleşmiş zarar, toplam 0,95 TL komisyon ve 647,60 TL toplam kasa ölçüldü. Bunlar sonuçların anlık görüntüsüdür, geleceğin tahmini değildir.
- Strateji zararlı rotasyona ve sırf küçük fiyat düşüşlerinde zarar kesmeye ağırlık vererek aynı kayıp-komisyon döngüsüne girmişti. Zararda rotasyon kaldırıldı; erken risk azaltımı ağır ve çoklu zaman diliminde doğrulanmış kötüleşmeyle sınırlı.
- Yeni girişler: 60dk genel soğuma, en fazla 6/gün, en fazla 6 açık pozisyon, en fazla %60 maruziyet, minimum %38 nakit rezervi, güçlü saatlik ve 15dk sinyal doğrulaması.
- Sermaye koruması: %4,5 sert stop; gözlenen %1,5 tepe sonrası yaklaşık %0,9 geri dönüşte, girişin üzerinde anlamlı kâr kalıyorsa iz süren çıkış; %3,5 sabit kâr alma. 1x sanal SHORT da bu korumaları kullanır.
- Yüksek volatilite, aşırı hızlı 15dk pump ve zayıf trend/komisyon adayları elenir. Öncelikli koruyucu kapanışlar günlük limitten etkilenmez.
- Geçmiş sanal işlemler, açık pozisyonlar ve 650 TL başlangıç referansı kesinlikle korunur. Kâra geçileceği garanti edilemez.

## 2026-11-23 — İki işlemlik olumsuz örneklemin AI'yi kilitlemesini önle

- Groq birkaç geçmiş zararlı sanal işlemi tüm adayların iptal gerekçesi yapmamalı; 20 kapanış altı örneklemin güvenilir tahmin olmadığı AI sistem bağlamında açıkça belirtildi.
- Model yine gerçek güncel sinyal, oynaklık ve gidiş-geliş ücretinden pozitif avantaj görmezse BEKLE seçebilir; risk kurallarını aşamaz veya emir boyutunu icat edemez.
- Kapanış sayısı ve gerçek geçmiş sonuçlar AI bağlamına veriliyor; yeni simüle işlem yaratılmıyor.

## 2026-11-23 — Sunucu karar gerekçelerinde Spot / SHORT netliği

- İşlem motorunun sanal AL/SAT günlükleri, karar açıklamaları ve 15dk koruyucu çıkışları artık gerçek spot alım-satım adını kullanır. İç hesaplamada mevcut uzun yön istatistikleri aynı kalır.
- Sunucu cüzdanı ve açık pozisyonlar değiştirilmedi.

## 2026-11-23 — Tek kasa arayüzünden eski demo mesajlarını kaldır

- Bot ekranında kalan eski yerel bot/demodan bahseden metinler silindi; yalnızca bir sanal cüzdan ve arka plan botunun otomatik emirleri açıklanıyor.
- Teknik adaylarda `SPOT AL` ile `SHORT AÇ` farklı ve açık adlandırılıyor.
- Güvenlik: ön yüzde manuel emir verilemez. Sunucu sanal cüzdanı korunur.

## 2026-11-23 — v0.9.10 Spot AL/SAT etiketlerinin netleştirilmesi

- Normal spot coin alımı `SPOT AL`, kapatılması `SPOT SAT` olarak Bot/Kasa/Kâr/İşlem Geçmişi ekranlarında gösterilir. Bunlar kaldıraçlı LONG kontratı değildir.
- 1x sanal SHORT aç/kapat işlemleri ayrı tutulur. Uygulama sadece arka plan sunucu kasasını gösterir; yerel cüzdan veya manuel emir ekranları kaldırılmıştır.
- Risk azaltımı çıkışları koruyucu zarar-kes yerine doğru `RISK_REDUCTION` tanısıyla raporlanır. Python/Flutter uyumluluk testleri güncellendi.
- Önceki sanal bakiye, 650 TL başlangıç ve işlem geçmişi sıfırlanmadı.

## 2026-11-23 — v0.9.9 Tam demo temizliği ve bağımlılık sadeleşmesi

- Eski yerel/demo cüzdanı, tarayıcı botu, manuel işlem ekranları ve onlara ait kullanılmayan model/servis/bileşen/test dosyaları GitHub deposundan silindi.
- `PremiumColors`, `PremiumSurface` ve `PremiumSectionTitle` yeni `premium_theme.dart` dosyasıyla tamamen sunucu botu ekranlarından bağımsız bir stile taşındı.
- Firebase, WebSocket ve shared_preferences gibi eski demo paketleri kaldırıldı; uygulama başlangıcı sadece bir GitHub sunucu cüzdanını okuyor.
- README tek sunucu mimarisini yansıtıyor. Kullanıcının `bot-data` sanal portföyü, alım/satımlar ve açık pozisyonlar korundu.

## 2026-11-23 — Hızlı risk azaltımı testi düzeltmesi

- Test senaryosundaki 15dk kapanış serisi yanlışlıkla karar eşiğinin üzerinde kalıyordu. Gerçek koşulu karşılayan kontrollü düşüş örneğiyle düzeltildi. Risk şartı ve mevcut kasa değiştirilmedi.

## 2026-11-23 — %65 kasa doluluk kilidi için kontrollü risk azaltımı

- Botun mevcut kasa yaklaşık %65 pozisyon taşıdığı için ne yeni LONG/SHORT açabildiği ne de onaylı rotasyon bulabildiği kontrol edildi. Gerçek 15dk verisine dayanan ve en az 90 dakikadır taşınan zayıf pozisyonlarda koşullu erken zarar sınırlaması eklendi.
- En fazla iki sanal risk azaltımı/gün, aralarında en az 90 dakika; zarar ve gerçek momentum şartı olmadan rastgele al-sat yok.
- Koruyucu stop emirleri daha yüksek önceliklidir, satış sonrası alım otomatik uydurulmaz. Test edilen simülasyon gerçekte kâr garantisi sağlamaz.

## 2026-11-23 — Tek kasa ekranı Flutter sözdizimi düzeltmesi

- Yeni Bot sekmesinin kapanış parantezindeki fazlalık Flutter Analyze tarafından tespit edilip düzeltildi; derleme ve widget testleriyle doğrulanır.

## 2026-11-23 — Tek beyin, tek kasa: yerel demo tamamen uygulamadan çıkarıldı

- Ana uygulama artık **tek** sunucu sanal cüzdanı açar. Yerel deneme motoru, yerel portföy, Firebase/local hesap oluşturma, manuel browser AL/SAT, sıfırlama ve yerel bot döngüsü uygulama başlangıcından ve ekranlardan çıkarıldı.
- Kasa / Radar / Bot / Kâr sekmeleri tek sunucu sanal durumunu okur. Radar sadece sunucu botunun onayladığı gerçek teknik adayları gösterir; sahte kullanıcı al/sat düğmesi yoktur.
- Başarılı sanal işlemlerin tamamı sunucunun mevcut bot-data kayıtlarında kalır; sunucu kasası asla resetlenmez.
- Önceden kullanılmış cihazlardaki eski yerel depolama bu güncellemeyle silinmez, fakat hiç açılmaz ve finansal toplamı etkilemez.
- Ana ekran yenileme ve son karar/işlem geçmişi aynı sunucu kaynaklarına bağlandı. Eski Flutter demo modülleri çalıştırılmıyor.

## 2026-11-23 — 15dk rotasyon regresyon düzeltmesi

- İlk Python testinde bulunan rotasyon aday listesi / mantıksal gösterge isim çakışması düzeltildi. Her simülasyonda testler geçmeden canlı kasa üzerine yeni sürüm uygulanmayacak.

## 2026-11-23 — Emir kilidi ve kısa vadeli hızlandırma

- Botun gerçekten işlemsiz kalma nedeni: 8 emir/gün sınırı dolmuştu ve risk motoru aday taramadan BEKLE diyordu. 16 kontrollü emir/gün sınırıyla düzeltildi.
- Gerçek Binance 15 dakikalık kapanışlarından 1s/4s momentum incelenir. En likit ve en hareketli seçili coinler, mevcut açık pozisyonlarla birlikte taranır. Var olmayan mum/sinyal üretilmez.
- Kısa vadeli ters trend yeni girişleri engelleyebilir; uygun gözlenen çıkış sinyalleri daha erken algılanır.
- Portföy rotasyonu en fazla 3/gün, 90 dakika aralıklı. Risk/komisyon/kapalı veri, nakit rezervi ve stop-loss korunur.
- 650 TL sanal kasa, bütün mevcut açık pozisyonlar ve geçmiş işlemler silinmedi.

## 2026-11-23 — Kâr ekranı ve sunucu botu etiketleri tekleştirildi

- Kâr ekranında sunucu botunun gerçekleşen sanal getirisi, açık LONG/SHORT, komisyonlu kapanan sonuçları, zirveden gerilemesi ve kazanma oranı öne çıkarıldı.
- Eski tarayıcı deneme performansı ayrı bir açılır bölümde tutulur; ana bot performansına eklenmez.
- Sunucu özet kartı 'ANA SANAL KASA · SUNUCU BOTU' olarak adlandırıldı; kullanıcı iki 650 TL hesabını tek kasaymış gibi görmez.
- Flutter ekran testleri yenilendi, kayıtlı gerçek sanal işlemler korunuyor.

## 2026-11-23 — Groq net getiri hedefi ve arayüz regresyon testleri

- Groq beynine onaylı adayların gerçek 6 saatlik momentum/oynaklık verileri ile kayıtlı net performans, kapanan işlemlerin gerçek net kâr/zararı ve %0,2 sanal gidiş-geliş komisyonu iletilir.
- Sistem rolüne sadece işlem sayısını değil komisyon sonrası risk ayarlı kasa büyümesini hedeflemesi ve üstünlük yokken beklemesi yazıldı. AI yalnızca onaylı aday seçebilir, risk sınırlarını aşamaz.
- Sunucu kasası ana görünümü, gerçek kasa eğrisi, ana portföy ve geçmişe giden butonlar için Flutter mobil testleri eklendi.
- Kullanılmayan eski HomeScreen sunucu özet metodu kaldırıldı. Sanal kasa değişmez.

## 2026-11-23 — Arayüz tek ana sunucu botu etrafında toplandı

- Panelde ana sanal kasa, sunucu botu performansı ve Groq AI kararları öncelikli; yerel demo cüzdanı ayrı, kapalı bölümde gösterilir.
- Portföy sekmesi sunucu LONG/SHORT pozisyonlarını ilk sırada açar. Yerel cüzdan mevcut verileri silinmeden ikincil panele taşındı.
- Bot sekmesindeki eski tarayıcı botu varsayılan kapalı gelişmiş bölüm altında; ana sunucu botundan ve kasasından bağımsız.
- Sunucu senkronizasyonu uygulama açıkken dakikada bir yapılır. Gerçek sanal işlem veya kâr uydurulmaz.

## 2026-11-23 — Tek sanal bot ana kartı

- Sunucu botu için ana ekran/kasa eğrisi/AI kararı/son işlem ve LONG/SHORT pozisyon kartları oluşturuldu. Tüm metrikler tek `ServerPaperSnapshot` üzerinden gelir.
- Yerel cüzdanın değerleri sunucu parasına eklenmez. Gözlem geçmişi olmayan kayıtlarda grafik uydurulmaz.

## 2026-11-23 — Büyüme odaklı sanal performans ve kâr koruması

- Sunucu botu artık başarılı döngülerde yalnızca gerçek piyasa gözlemlerine dayalı kasa grafiği (son 576 gözlem), net sanal büyüme, net kapanan sonuç, ücretler ve zirveden gerileme verilerini saklar.
- LONG ve SHORT sanal pozisyonlarda gerçek gözlemlenmiş zirve/dip sonrası yeterli kârı geri vermemek için takip eden kâr koruması uygulanır; sabit stop-loss ve kâr al kuralları önceliklidir.
- Yeni sanal emirler eskisi gibi veri tazeliği, günlük limit, nakit rezervi ve maruziyet sınırlarına bağlıdır; garanti edilen kâr veya uydurma işlem yoktur.
- Önceki 650 TL sanal kasa ve tüm açık pozisyonlar korunur.

## 2026-11-22 — Rotasyonun AI durumundan doğru ayrılması

- Botun teknik portföy rotasyonu satışı artık "koruyucu zarar-kes" gibi gösterilmez. İşlem emri mevcut kuralların onayladığı sanal çıkıştır; AI bu çıkışı durdurmaz.
- Regresyon testi eklendi; kayıtlı açık pozisyonlar ve mevcut sanal işlem geçmişi aynen korunur.

## 2026-11-22 — Portföy doluluk kilidi ve sanal rotasyon

- %65 maruziyet sınırı portföyde altı SPOT pozisyon açılınca yeni girişleri durduruyordu. %60+ maruziyette, yalnızca en az 90 dakikalık, hafif zarar/kâr bölgesinde momentum kaybeden SPOT pozisyonu ve daha güçlü yeni aday varsa bir kez/UTC gün kontrollü rotasyon satışına izin verildi.
- Güçlü aday yoksa veya kapanış büyük zarar yaratacaksa pozisyonu sırf hareket olsun diye satmaz. Koruyucu kâr al/zarar kes çıkışları her zaman önceliklidir.
- Bir satış sonrası yeni giriş aynı döngüde zorlanmaz; adayın sonraki taze fiyatlı döngüde geçerli kalması gerekir. 8 işlem/gün sınırı korunur.
- Rotasyon / bekleme / günlük limit / zararlı rotasyon engelleme regresyon testleri eklendi. Mevcut sanal kasa ve işlemler sıfırlanmadı.
- Harici zamanlayıcı olmadan GitHub Actions kesintisiz arka plan çalışması sağlamaz.

## 2026-11-22 — Zamanlayıcı görünümü regresyon testleri ve sürüm

- Bot ekranındaki GitHub son schedule bilgisinin eski sunucu kayıtlarından uydurulmadığı Flutter testleriyle doğrulanır.
- Uygulama paket sürümü `0.9.6+13` olarak yükseltildi.

## 2026-11-22 — GitHub schedule kanıtı ve mobil görünürlük

- GitHub bot ekranında son otomatik tetik veya 'henüz doğrulanmadı' durumu ve son gerçek çalıştırma türü gösterilir.
- Ayrıca cüzdanı hiç okumayan ve sanal emir üretmeyen bağımsız `GitHub Cron Diagnostic (No Trades)` workflow'u eklendi; her saat 11. ve 41. dakikalarda gerçek schedule sinyali kontrol eder.

## 2026-11-22 — GitHub-only gerçek cron tanısı

- Botun 5 dakikalık cron tetikleyicisi `2-57/5 * * * *` biçimiyle yeniden kaydedildi.
- Sunucu botu gerçek GitHub event türünü (`push`, `workflow_dispatch`, `schedule`) ve son schedule olayını saklar. Kod güncellemesi otomatik çalışma diye gösterilmez.
- Eski sanal cüzdan dosyası uyumluluğu test edildi; 650 TL kasa, LONG/SHORT pozisyonları ve işlem geçmişi korunur.
- GitHub schedule olaylarının zamanında ulaşması garanti değildir.

## 2026-11-22 — Groq HTTP 403 istemci imzası düzeltmesi

- Groq API HTTP 403 cevabı testte tespit edildi. Python `urllib` varsayılan User-Agent'i Groq edge güvenlik katmanında engellenebildiği için açık `SanalTraderPaperBot/1.0` istemci başlığı eklendi.
- İstek başlığı için anahtar gizliliği ve JSON yanıtı kontrol eden regresyon testi eklendi.
- Her durumda gerçek para veya emir gönderme işlevi bulunmaz; sanal cüzdan sıfırlanmadı.

## 2026-11-22 — Groq bağlantı tanılama iyileştirmesi

- İşlemsiz AI sağlık testi artık API yanıtındaki yalnızca HTTP hata kodunu gösterir; gizli anahtarı veya hassas hata gövdesini yayımlamaz.
- GPT-OSS-20B bağlantısı `reasoning_effort: low` ve 1024 çıktı token sınırıyla güncellendi.
- AI API'si yanıt vermezse strateji motoru mevcut sanal risk kurallarıyla çalışmayı sürdürür.

## 2026-11-22 — AI gerçek bağlantı kontrolü ve dış zamanlayıcı

- İşlemsiz Groq bağlantı sınaması bağımsız GitHub Actions akışına eklendi; cüzdanı/işlem geçmişini değiştirmez.
- Cloudflare Workers ücretsiz cron köprüsü hazırlandı. Her 5 dakikada bir mevcut GitHub `Free Scheduled Paper Bot` workflow'unu `workflow_dispatch` ile tetikleyebilecek. Kurulum yönergeleri `cloudflare/README.md` altında.
- Gizli GitHub fine-grained token yalnızca Cloudflare secret alanında tutulur. Worker HTTP isteklerinden emir başlatılamaz.
- Altı Node birim testi ve CI eklendi. Kesintisiz çalışma henüz Cloudflare hesabında deploy yapılmadığından doğrulanmadı.
- 650 TL sanal kasa, açık pozisyonlar ve geçmiş işlemler değiştirilmedi.

## 2026-11-22 — Ücretsiz AI karar katmanı (paper trading)

- Bot ekranında AI bağlantı/karar/hata durumları ve gerekçesi gösterilir.

- Sunucu botuna opsiyonel Groq `openai/gpt-oss-20b` karar katmanı eklendi.
- AI yalnızca risk motorunun önceden onayladığı ilk beş BUY/SHORT adayından birini seçebilir veya WAIT diyebilir. STOP/TP kaynaklı SELL/COVER emirleri AI kontrolüne takılmaz.
- `GROQ_API_KEY` GitHub Actions secret olarak tanımlanmadıkça mevcut kural tabanlı motor değişmeden çalışır. Hatalı/limit aşılmış AI yanıtında da kural motoruna geri döner.
- AI karar durumu `bot-data/state.json` içinde `aiBrain` ve `decisionPlan.aiBrain` olarak görünür. Hiçbir gerçek emir gönderilmez.
- Önceki sanal işlemler, cüzdan ve pozisyonlar korunur.
- GitHub Actions schedule hâlâ garantili 7/24 servis değildir; ayrı barındırma ihtiyacı devam eder.

# SanalTrader — Güncelleme Geçmişi

## v0.9.3 — 2026-11-22: Zamanlama ve işlem yapmama nedenleri

- Düşük sinyal ret nedenlerini, ilk 36 dışındaki hacimli hareketli coin taramasını ve sık tekrar eden işlerde kararın silinmemesini sınayan yeni Python testleri eklendi.

- Kayıtlarda son başarılı sunucu fiyat kontrolü 22.29 TR iken saat 22.42'ye kadar planlı beş dakikalık iş görünmedi. GitHub Actions cron saati `3-58/5` biçimine alındı; **GitHub yine gecikme/atlama yapabilir**, kesintisiz sunucu değildir.
- Sanal botun teknik taraması 24 likit coin yerine ilk 36 yüksek hacimli coin, ek olarak 10 yükselen ve 10 düşen uygun coin ile genişletildi.
- Sunucu karar motoru uygun teknik sinyal çıkmadığında numaralı gerekçelerini ve piyasa evreni / grafik sayısı / detaylı incelenen sayısını saklar. Bot kartında BEKLE'nin nedenleri gösterilir.
- Art arda çok yakın tetiklenen bot işlerinde güncel karar metni mükerrer görev mesajı ile ezilmez.
- İşlem ve risk sınırları, önceki sanal pozisyonlar ve yalnızca public veri kullanımı değişmedi.



## v0.9.2 — 2026-11-22: Otonom AL / SAT / LONG / SHORT karar motoru

- Flutter'daki Karar Merkezi son sunucu kararını ve adayları açılır panelde gösterir; eski bot-data şeması ile mobil dar ekranda yeni testler eklendi.
- README üzerinde spot AL = 1x LONG yönü; ayrı kaldıraçlı LONG kontratı bulunmadığı ve SHORT'un ayrı simülasyon olduğu netleştirildi.

- Bot → Sunucu Botu ekranına katlanabilir Karar Merkezi eklendi: son otomatik karar, piyasa yönü, seçim gerekçesi, seçilen coin ve ilk beş güçlü aday.
- Tüm kararlar sunucunun kalıcı bot-data kayıtlarından okunur; yerel bot ya da sanal kasa yerine geçmez.
- Flutter sürüm numarası 0.9.2+11 olarak güncellendi.

- Ücretsiz sunucu botu piyasa durumuna göre tek başına **spot AL (1x LONG), spot SAT (kapat), sanal 1x SHORT aç, SHORT kapat veya BEKLE** kararı verir.
- Son görülen spot fiyat, saatlik geçmiş, BTC piyasa rejimi, oynaklık, maliyet payı, açık pozisyon, nakit ve maruziyet birlikte değerlendirilir.
- Koruyucu pozisyon kapatma kararları yeni girişten önce işlenir, günlük emir sınırına takılmaz; aşırı eski veya tutarsız grafikle yeni işlem açılmaz.
- İşlem yapılmayan döngülerde bekleme nedeni ve değerlendirilen adaylar kayda geçer; sanal başarı veya işlem uydurulmaz.
- Uçtan uca otomatik BUY/SELL/SHORT/COVER/WAIT, veri kesintisi ve risk durum testleri eklendi.



## v0.9.1 — 2026-11-22: Sayfa bağlantıları ve sanal cüzdan bütünlüğü

- Kullanıcı rehberlerindeki eski mimari ifadeleri düzeltildi; yerel bot, ayrı sunucu sanal kasası, LONG/SHORT simülasyon sınırları ve GitHub cron durumunun ayrımı açıklandı.

- GitHub Actions cron tanımı standart `*/5 * * * *` hâline getirildi. Zamanlanmış ilk gerçek tetikleme henüz doğrulanmadı; GitHub işleri geciktirebilir veya atlayabilir.

- SharedPreferencesAsync testleri resmi in-memory platform sahte uygulaması üzerinden çalıştırılıyor; eski setMockInitialValues yeni API ile uyumlu değildi.

- Yerel bot otomatik açılma/migrasyon ve aynı sekmede eşzamanlı sanal emir/sıfırlama sırasını koruyan yeni otomatik testler eklendi.

- Yerel sanal kasada eşzamanlı manuel/otomatik AL/SAT sıralı kayıt kuyruğuyla çakışmadan işleniyor; reset işlemi de sıraya giriyor.
- Bu koruma yalnızca aynı uygulama sekmesinde geçerli; ayrı sekmeler için paylaşılan sunucu işlemselliği gerekebilir.

- GitHub public read-only GET isteklerindeki CORS preflight'a neden olabilen Cache-Control header'ı kaldırıldı; URL yenileme parametresiyle cache kontrolü sürüyor.
- Bot ve Kâr ekranlarında gerçekleşmiş LONG ve SHORT sanal kapanışlarına ait ayrı öğrenme istatistikleri gösteriliyor.

- Yerel botun zarar koruma satışları günlük emir limiti dolduğunda da yapılabilir; limit yeni alışlara uygulanır.
- Bayat fiyat, portföy, bot ve kâr ekranlarında sanki güncelmiş gibi değerlenmez; bu durumda yeni alım riski durdurulur.
- Acil satış ve stale varlıkla yeni işlem engelleme testleri eklendi.

- Türkçe metinli sunucu yanıtı için entegrasyon testinde doğru UTF-8 HTTP kodlaması uygulandı.

- Manuel spot ve otomatik yerel emrin aynı anda çakışması ile sürmekte olan işlemin ortasında yerel kasa sıfırlanması engellendi.
- Sıfırlama onayı yerel hesapla sınırlı olduğunu, sunucu botunun kasası ve SHORT pozisyonlarının korunacağını açıkça belirtiyor.
- Coin detayında yerel spot işlem alanı ile sunucu 1x SHORT işlemleri ayrıldı.
- Ana Panel'deki Güncelleme Geçmişi etiketi v0.9.1'e güncellendi.

- Ortak sunucu snapshot/parsing, HTTP başarısızlığı, eski şema uyumu, LONG/SHORT görünümü ve geçmiş ekranında gerçek verinin yenilenmesi için testler eklendi.

- Ortak sunucu işlem geçmişi için ValueListenable import eksikliği düzeltildi; Performans ekranı widget testi ortak sunucu durumu parametrelerine uyarlandı.

- Tek bir read-only sunucu botu bağlantısı Panel, Portföy, Bot ve Kâr ekranları arasında paylaştırıldı; ayrı 650 TL yerel cüzdan korunuyor.
- Sunucu botunun tüm kayıtlı LONG/SHORT işlemleri yeni tam işlem geçmişinde görülebilir; ekran açıkken yenilenen durum bildirilir.
- Yeni kurulumda tarayıcıdaki yerel otomatik bot açık gelmez; eski kullanıcı tercihi olduğu gibi taşınır.
- Sunucu veri erişim hataları ve eski kayıtlar net biçimde işaretlenir; sunucu kasası yerel verilere karıştırılmaz.
- Sunucu ve yerel pozisyonların ayrımını açıklayan ekran başlıkları ve mobil testler güncellendi.


## v0.9.0 — 2026-11-22: 1x sanal LONG / SHORT

- SHORT kapanış kâr öğrenmesinde referans alınan teminat değişkeni düzeltilerek testte görülen çalışma hatası giderildi.

- LONG/SHORT yön öğrenmesi için gerçekleşen sanal kapanış, kayıp, örneklem ve sınırlı puanlama birim testleri eklendi.

- Bot tamamlanan gerçek sanal LONG ve SHORT satış/kapatış net getirilerinden ayrı ayrı öğrenir; üç kapanışa kadar yön bazlı ödül verilmez.
- Geçmiş kârlılık tercihi maksimum ±0,12 skor ile sınırlandırılır; trend teyidi, nakit ve maruziyet kuralları değişmez.

- Sunucu botu ekranında LONG/SHORT pozisyonlar, sanal teminat, son işaret fiyatı ve SHORT aç/kapat işlem etiketleri gösteriliyor.
- Flutter sürümü 0.9.0+9 olarak güncellendi.

- GitHub Actions Python backend paketinin modül kipinde başlatılmasına geçirildi; yalnızca zamanlanmış çalışmada görülen import hatası giderildi.

- SHORT P/L, komisyon, teminat, ani fiyat sıçraması, eski cüzdan geçişi ve düşüş sinyalinden uçtan uca otomatik emir testleri eklendi.

- Botun otomatik seçiminde güçlü düşüş trendi (teknik puan ≤ -0,70) için sanal SHORT, yükselişte LONG sinyali uygulanır.
- Aynı coinde ters yönlü iki pozisyon engellenir; toplam maruziyet, nakit rezervi, BTC rejimi ve volatilite sınırları korunur.

- SHORT ayrı sanal teminatı ve fiyat farkıyla portföy değerine katılır, eski cüzdanlar uyumlu yüklenir.
- SHORT ters fiyat %6 zarar kes, %8 olumlu fiyat hareketinde kâr alma, teminat ve trend dönüşü kontrolü uygulanır.
- LONG/SHORT toplam maruziyet hesaplanır; riskten çıkışlar günlük yeni emir sınırı aşıldığında da kontrol edilir.

- Ayrı teminatlı 1x sanal SHORT aç/kapat, komisyonlu net sonuç ve portföy değerlemesi motoru eklendi.
- Eski LONG cüzdanı silinmez. Spot fiyatlarla yapılan bu model gerçek vadeli kontrat, funding, borçlanma bedeli veya likidasyon motoru değildir.


## v0.8.0 — 2026-11-22: Ücretsiz zamanlanmış sunucu sanal botu

- Tarayıcıdan bağımsız GitHub Actions botu yaklaşık 5 dakikada bir Binance public spot fiyatlarını kullanarak yalnızca sanal işlem denemeleri yapar.
- Sanal sunucu cüzdanı `bot-data/state.json` dalında tutulur. Tarayıcıdaki yerel 650 TL cüzdanı silinmez, bu cüzdanla henüz birleşmez.
- Bot sekmesinde ayrılmış sunucu sanal kasası, son kontrol, işlem listesi ve kâr/zarar durumu salt okunur canlı olarak gösterilir.
- GitHub workflow dispatch menüsünden run / pause / resume / reset yönetimi yapılır. Bunlar gerçek emir değildir.
- Bu, ücretsiz GitHub cron nedeniyle garanti edilmiş saniyelik kesintisiz VPS sistemi değildir.


## v0.7.0 — 2026-11-22: Komisyonlu ileri-test ve bot karar incelemesi

- Performans ekranındaki aşağı kaydırılarak görünen boş sonuç alanı için Flutter testine gerçek kaydırma davranışı eklendi.

- Kâr ekranındaki ileri-test kartı bileşen kapanış hatası düzeltildi ve gereksiz null-assertion uyarısı kaldırıldı.

- İleri-test: yetersiz veri, yatay piyasa komisyonu, geri dönüş, eğitimden holdout'a veri sızmaması ve JSON kayıt testleri eklendi.
- Bot ve Kâr ekranlarında ileri-test kartları null güvenli biçimde gösteriliyor.

- Bot ve Kâr ekranlarında gerçek işlemlerden ayrı, maliyetli geçmiş strateji denemesinin getirisi, al-tut kıyası, işlem sayısı ve en yüksek gerilemesi gösteriliyor.

- Saatlik piyasa geçmişi düzenli yenilenir; yeni saatlik kapanış eskisiyle aynı uzunlukta olsa bile tarihine göre yenilenir ve WebSocket anlık fiyatı korunur.
- Bot yeni gerçek işlemlerden ayrı, yaklaşık saatte bir komisyonlu ileri-test çıktısını yerel olarak kaydeder.

- Gerçekleşen sanal emirlerden tamamen bağımsız ileri-test istatistikleri BotState içinde yerel olarak saklanıyor.

- Son 24 saatlik görülmemiş fiyat üzerinde yalnızca geçmişe bakan, %0,1 komisyon + %0,05 varsayımsal kayma içeren uzun pozisyon simülasyonu.
- Strateji net getirisi, maliyetli al-tut kıyası, kapanan sanal test işlemleri ve maksimum gerileme ölçümleri.
- Bu geçmiş testi gerçek sanal cüzdan işlemi değildir, hesap bakiyesini değiştirmez ve kazanç garantisi sayılmaz.


## v0.6.0 — 2026-11-22: Geniş piyasa radarı ve net kârla öğrenme

- Bot ekranına 'Geçmiş veriden yeniden eğit' eklendi; öğrenilen sanal gerçekleşmiş işlem kârı silinmeden tarihsel eğitim yenileniyor.
- CoinGecko yedek REST piyasası ilk 250 coin ile genişletildi; kullanım rehberleri ve piyasa sınırları güncellendi.

- 240 coin üst sınırı kaldırıldı: yalnızca yeterli hacmi ve geçerli fiyatı olan Binance USDT Spot pariteleri taranır, kaç coin olduğu güncel listeye göre değişir. API ve cihaz kaynakları sınırsız değildir.
- Ana sayfa 5 coinlik hızlı özet gösterir; tüm coinler ayrı Radar sayfasında lazy list olarak açılır.
- Binance 24hr piyasa verileri tek tüm-piyasa REST çağrısından yenilenir, URL uzunluğu sorunu engellenir.

- Net gerçekleşen kâr öğrenmesi, sahte sonuç engeli, emir komisyonu, kayıp, kazanç ve 72 üzeri coin keşfi için yeni testler.
- Boş piyasa radarı ve boş bot satış geçmişi senaryoları arayüz testleriyle korunuyor.

- Bot paneline gerçekleşmiş sanal işlem kârı, kazanma oranı ve Performans Merkezi kısayolu eklendi.

- Alt navigasyon Panel / Radar / Portföy / Bot / Kâr sekmeleri oldu; geçmiş işlemler menüden veya performans sayfasından erişiliyor.
- Botun sanal emir sonucundan dönen gerçek işlem kaydı, net gerçekleşmiş kâr öğrenmesine bağlandı. Uydurma emirlerden kazanma oranı üretilmiyor.

- Yeni Radar sayfası: hacim, yükselenler, düşenler, teknik adaylar ve anlık arama.
- Yeni Performans sayfası: açık portföy değeri ve yalnızca kapanan sanal bot emirlerinden hesaplanan net kâr, komisyon, kazanma oranı ve coine göre sonuçlar.

- Hacim filtreli Binance USDT spot evreni 72'den 240 sembole genişletildi; 6 saatlik yenileme, eski pozisyon sembollerini koruma ve 64 sembollük tarihsel eğitim taraması eklendi.
- Çoklu abonelikli uzun URL yerine Binance'in tüm piyasa mini-ticker WebSocket akışı ve toplu mesaj ayrıştırıcısı kullanılıyor.
- USDT/TRY dönüşüm oranı 2 dakikadan daha eskiyse taze piyasa fiyatı oluşturulmuyor.

- Gerçek sanal bot emirlerinden öğrenilen net kâr bilgisi BotState içinde kalıcı saklanıyor; coine özel birikmiş kâr/zarar gelecekteki aday sırasını sınırlı etkiliyor.

- Yalnızca gerçekten tamamlanmış sanal BOT satışlarından net gerçekleşmiş kâr/zarar, işlem maliyeti, coin bazlı kazanma oranı ve temkinli performans öğrenmesi eklendi.
- Öğrenme geçmişte uydurulmuş işlemlere, fiyat yönü isabetinin tek başına kâr olduğu varsayımına veya sınırsız risk almaya dayanmaz.


## v0.5.0 — 2026-11-22: Premium arayüz — Zümrüt & Altın

- Premium widget testlerindeki ekran boyutu ayarı Flutter test API'sine uyarlandı.

- Dar mobil ekranda gerçek sanal bakiye, ölçülmeyen bot doğruluğu ve güncelleme kısayolu widget testleriyle kontrol edildi.

- Bot, coin detay, teknik analiz ve güncelleme ekranları dahil diğer sayfalar aynı premium renk sistemiyle uyumlu hâle getirildi.

- Referans premium görünüm, Flutter widget'larıyla gerçek veriye bağlı koyu zümrüt/altın tasarıma dönüştürüldü.
- Ana sayfaya kompakt sanal portföy hero kartı, gerçek kâr/zarar, getiri ve açıklamalı BTC grafiği eklendi.
- En hacimli coinler cam panelli piyasa listesinde, fiyat ve gerçek değişim oranlarıyla görüntüleniyor; arama için tümünü gör/daralt açılır alanı var.
- Uzman bot kartı BTC trendini, ölçülmüş teknik doğruluğu ve piyasa riskini gösteriyor; uydurma yapay zekâ güven skoru yok.
- BTC teknik göstergeleri RSI, MACD, trend ve oynaklık kartları olarak özetleniyor; detay ekranına geçiş korunuyor.
- Güncelleme Geçmişi ana ekrana taşındı ve üst başlık, gezinme ile veri giriş alanları premium temaya geçirildi.
- Görsel prototipteki örnek ₺1.248.730 gibi rakamlar uygulamaya alınmadı; ₺650 başlangıç sanal bakiyesi ve hesaplanan gerçek portföy bilgileri korundu.


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
