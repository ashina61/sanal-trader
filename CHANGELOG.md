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
