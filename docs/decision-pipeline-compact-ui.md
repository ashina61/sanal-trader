# SanalTrader v0.9.24 — Karar Motoru ve Kompakt Mobil Arayüz

## Tek kasa ve altı aşamalı onay

Mevcut Python motoru aynı 650 TL başlangıçlı tek sanal kasayı yönetir;
önceki açık SPOT/1x sanal SHORT pozisyonları ve geçmiş korunur. Altı farklı
ücretli Grok ajanı veya ek cüzdan kurulmaz. Aşağıdaki aşamalar birlikte,
deterministik kayıt (executionPipeline) üretir:

1. PULSE: Binance herkese açık emir defterinin ilk 5 kademesindeki teklif
   ve talep nominal hacim dengesini gözler. Tek seferlik bir örneklemdir.
2. IMPACT: Gerçek REST depth 20 kademe üzerinden planlanan tutarın görünür
   derinlikte yaklaşık ağırlıklı alış/satış fiyatını hesaplar.
3. EDGE: Gelecekteki fiyatı veya kesin avantajı uydurmaz; görünür kayma
   ve gidiş-dönüş yaklaşık ücretleri ölçer. Ek getiri tahmini henüz
   kalibre edilmedi. Spread >%0,8, orta fiyattan kayma >%0,8,
   varsayımsal gidiş-dönüş sürtünmesi >%1,2 giriş ret nedenidir.
4. SIZE: Önceki risk motorunun zaten onayladığı tutarı baz alır;
   görünür defterde hedef büyüklüğün tamamı karşılanamıyorsa girmez.
   Orijinal kasa/pozisyon sınırları değişmez.
5. ENTRY: Gerçek bir emir gönderilmez. Sanal yeni BUY/SHORT için
   gözlenen defterin ağırlıklı fiyatı kullanılır. Gerçek gerçekleşme,
   bekleyen emir ve garantili fill olduğu iddia edilmez.
6. EXIT: Mevcut koruyucu SPOT SAT / sanal SHORT kapat kuralları,
   tüm grafik, AI ve emir defteri sorgularından önce çalışır.
   Mevcut %-4,5 stop, kâr al ve kâr koruma kuralları aynen korunur.

Emir defteri yalnız risk motoru ve Groq'un (yapılandırılmışsa)
seçtiği son BUY/SHORT adayında sorgulanır. Gerçek Market veri kaynağı
yanıt vermezse yeni giriş engellenir; çıkışlar korunur. FakeMarket
testlerinde emir defteri bulunmaması UNSUPPORTED olarak açıklanır ve
özel test sağlayıcısının davranışı bozulmaz. Bu, tarihsel geçmişi yeniden
yazmaz veya geçmiş kârlılık kanıtı sağlamaz.

## Mobil arayüz

- Kasa: net sanal bakiye, değişim, nakit, pozisyon, işlem sayısı ve son
  karar ilk ekranda. Ayrıntılı pozisyon ve teknik sağlık açılır.
- Radar: likit parite/aday/DEX havuz özetleri ilk sırada. Teknik
  adaylar, ücretsiz DEX keşfi ve doğrulanmış akıllı para katmanı ayrı
  açılır. Doğrulanmamış adresler satın alma emri değildir.
- Bot: kısa durum/son karar, iki sütunda altı aşama, açılır karar
  ayrıntıları ve gelişmiş tanılar.
- Kâr: net sonuç ve temel performans ilk ekranda. Ayrıntılı kasa
  grafiği isteğe bağlı açılır; tam işlem geçmişi ayrı sayfada korunur.
- Sayfalar 320 piksel Android genişliğinde test edilir. Mobil arayüz
  yalnızca aynı sunucu durumunu okur.

## Veri, sınırlamalar ve ücretler

Emir defteri kaynağı Binance public data-api.binance.vision
/api/v3/depth?symbol=...&limit=20. Sorgu ücretli API anahtarı gerektirmez
ancak ağ, gecikme ve rate limit riski taşır. Sürekli WebSocket veya
saniyelik bot döngüsü kurulu değildir. Anlık defter gördüğümüz fiyat,
garantili piyasa emri dolumu değildir. Short yalnız 1x sanal referanstır;
borsaya açılmış borçlu pozisyon değildir.

Testler: python3 -m unittest discover -s backend/tests -v
ve flutter test. Flutter sürümü 0.9.24+30.
