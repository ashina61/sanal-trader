# SanalTrader — Sanal Kripto Trading ve Öğrenen Bot

Gerçek kripto piyasası TRY fiyatlarını **sadece sanal ₺650** başlangıç bakiyesiyle alıp satmak için Android öncelikli örnek uygulama.

> **Hiçbir yerde gerçek emir, borsa hesabı, para yatırma, para çekme veya cüzdan anahtarı yoktur.** Bu uygulama bir paper-trading simülatörüdür; yatırım tavsiyesi değildir.

## Güncelleme Geçmişi

Uygulamanın üst menüsündeki **güncelleme simgesini** açarak bütün sürümlerin geçmişini görebilirsin. Notlar `assets/changelog.json` dosyasından gelir; geliştirici ayrıntıları `CHANGELOG.md` dosyasında tutulur. Yeni kaynak kod değişiklikleri aynı committe bu iki dosyaya da yazılmazsa GitHub Actions kontrolü başarısız olur.

**Teknik analiz:** Coin detayındaki **Botun teknik analizini gör** butonu RSI, MACD, EMA20/50, 48 saatlik destek/direnç, ATR, hacim ve (varsa) tamamlanmış mum formasyonlarıyla yorumları gösterir. Bot bu göstergelerin geçmişte tutarlı yön gösterip göstermediğini 15 dakikalık sonuçlarla ölçerek teknik göstergelere verdiği ağırlığı sınırlar ve zamanla değiştirir. Bu, insan uzman veya kesin tahmin sistemi değildir.

## Canlı piyasa ve otomatik bot

**Canlı web:** https://ashina61.github.io/sanal-trader/

- Güncel, likit USDT spot coinleri için Binance public **tüm piyasa miniTicker WebSocket** ve gerçek **USDT/TRY** piyasa kuru ile TL fiyatları güncellenir; işlem API anahtarı yoktur.
- Açılışta Binance REST üzerinden 7 günlük saatlik geçmiş ve güncel fiyatlar alınır. Erişim sorunu olursa CoinGecko yedek kaynaktır. **İkisi de erişilemezse işlem yapılmaz**.
- Kullanıcının bu talebiyle kişisel sanal bot **v2 ilk açılışında otomatik etkinleşir**. Bot sekmesindeki anahtardan istediğin zaman durdurabilirsin; durdurma kararı sonraki açılışlarda korunur.
- Uygulama açıkken bot 45 saniyelik döngülerle yeni piyasa fırsatlarını değerlendirir. Her döngüde **en fazla bir sanal emir** verebilir; işlem yoksa sinyal ve risk sınırları beklenir.
- Fiyatlar **canlı işlem garantisi değildir**; WebSocket bağlantısı kopabilir, piyasa verileri engellenebilir. Sitede **CANLI** veya yedek kaynak durumu gösterilir.
- GitHub Pages **arka plan bot sunucusu değildir**. Tarayıcı kapanınca bot çalışmaz, kapalı kaldığı süre için geriye dönük işlem uydurulmaz.

## Sitede öğrenen bot (sanal işlemler)

**Web:** https://ashina61.github.io/sanal-trader/

Ana sayfada **Bot** sekmesine gir, riskleri oku ve **Botu aç** anahtarını etkinleştir. Bot başlangıçta **kapalıdır**. Açıkken güncel veriler üzerinden kendi başına **sanal** alım/satım yapar ve yaptığı işlemlerin nedenini bot günlüğüne ekler.

- Üç fiyat uzmanının (kısa trend, 24s momentum, ters yön) ağırlıkları en az 15 dakika sonra gelen **yeni fiyatlarla** değerlendirilerek güncellenir. Bu, basit bir **online öğrenme algoritmasıdır**, büyük dil modeli veya kâr garantisi değildir.
- En fazla toplam portföyün %12'si kadar yeni alış; tek coinde %25; toplam coinlerde %65; en az %30 sanal nakit rezervi.
- Günlük en fazla 8 emir; aynı coinde 30 dakika tekrar bekleme (koruyucu satış hariç); yaklaşık %6 zarar koruması ve %8 kâr alma.
- 90 saniyede bir piyasa yenilemesi denenir. **Tarayıcı kapanırsa bot da durur.** GitHub Pages üzerinde sürekli çalışan bir sunucu yoktur.
- Botun ayarları ve öğrenme sayıları tarayıcıdaki yerel depolamada tutulur. Site verilerini temizlersen silinebilir.
- Bot ve sen manuel sanal alım/satım için aynı doğrulama motorunu kullanırsınız. **Gerçek borsa bağlantısı, anahtar, para transferi bulunmaz**.

Ayrıntılı rehber: **[BOT_REHBERI.md](BOT_REHBERI.md)**.

## Ücretsiz sunucu botu · v0.8.0

**Yeni:** Sunucu sanal botu için GitHub Actions beş dakikalık zamanlama kuruldu. Bot `bot-data` dalına açık, kişisel veri içermeyen sanal durumunu yazar. **Bot** sekmesindeki sunucu kartı kasa/son işlem/son çalışma durumunu gösterir. Sunucu kasası ile tarayıcıdaki yerel kasa şu anda iki ayrı test kasasıdır; karışmamaları için farklı etiketlenir. Ücretsiz zamanlama tam kesinlikte çalışmayabilir.

Sunucu bot yönetimi: https://github.com/ashina61/sanal-trader/actions/workflows/paper-bot.yml

## Kâr odaklı sanal işlem botu · v0.6.0

**Yeni:** Ana gezinme **Panel · Radar · Portföy · Bot · Kâr** olarak ayrıldı. Radar yükselenleri, düşenleri, hacimli coinleri ve teknik sinyalleri listeler. Kâr ekranı botun gerçekten gerçekleştirdiği sanal satışlardan **komisyon dahil net sonuç** hesaplar; henüz satılmamış pozisyonlar gerçekleşmiş kâr sayılmaz.

Bot kapalı tarayıcıda işlem yapmaz. Kazanç garantisi, gerçek borsa emri veya para transferi yoktur. **Geçmiş veriden yeniden eğit** butonu strateji ağırlıklarını günceller; botun gerçek sanal işlem performansı ve kullanıcının açık/kapalı seçimi korunur.

## Geniş altcoin taraması ve öğrenen bot

- Sabit sayı sınırı olmadan Binance public spot listesinden **24 saatlik USDT hacmi en az 1 milyon olan uygun likit coinler** seçilir. Desteklenmeyen, düşük hacimli, sabit değerli ve kaldıraçlı ürünler elenir. Tam kripto evreni değil; ilk aşamada **Binance'te likit USDT spot çiftleri** kapsamındadır.
- Canlı fiyatlar WebSocket ile güncellenir. USDT/TRY piyasa çifti kullanılarak sanal TL karşılığı hesaplanır.
- En likit 64 coinin yaklaşık 7 günlük saatlik kapanış fiyatları geçmiş strateji eğitimine alınır (API erişimi varsa).
- Öğrenme motoru **son 24 saatlik veriyi eğitimden ayırır** ve o bölümdeki yön tahmini doğruluğunu basit momentum tahminiyle karşılaştırır. Bu, **kârlılık veya ileriye dönük performans garantisi değildir**.
- Geçmiş veriden eğitim başarılı değilse **bot yeni AL emri açmaz**; güvenli şekilde bekler. Kullanıcı Bot sekmesinden durdurabilir.
- Canlı olarak yeni fiyatlar geldikçe sonraki fiyatla karşılaştırılmış tahminlere göre strateji ağırlıkları güncellenir. Sonuçlar bu tarayıcıda saklanır.
- Piyasa sekmesinde coin arama ve gerçek USDT hacmine göre sıralama bulunur. Çok küçük tokenlerin TL fiyatı yeterli ondalık hassasiyette gösterilir.
- Binance API/CORS/ağ/rate-limit sorunlarında CoinGecko'nun piyasa değeri sıralamasındaki uygun, hacimli **erişilebilen ilk 250 uygun coinden oluşan yedek liste** denenir. Bu veri periyodik yenilenir; WebSocket kadar canlı değildir. Sahte fiyat oluşturulmaz.

**Sınır:** Tarayıcı kapalıyken bot işlemez. 7/24 işlem ve cihazlar arası güvenilir öğrenme için sunucu tarafı altyapı gerekir.

## Bu sürümde neler var?

- Bitcoin, Ethereum, Solana, XRP, BNB, DOGE için CoinGecko TRY piyasa verisi
- Yaklaşık 90 saniyede yenilenen piyasa ve son 7 gün fiyat eğilimi grafiği
- ₺650 başlangıç bakiyesi, ₺5 minimum işlem, %0,1 **varsayımsal** komisyon
- Piyasa fiyatından **anlık sanal alım ve satım**; bakiye kontrolü
- Maliyet bazlı pozisyon takibi ve gerçekleşmiş kâr/zarar
- Başlangıç bakiyesine göre toplam portföy getirisi
- Sanal işlem geçmişi ve portföy sıfırlama
- Varsayılan **yerel saklama** (`shared_preferences`)
- İsteğe bağlı **Firebase Anonymous Auth + Firestore** saklama ve sunucu tarafında atomik cüzdan güncellemesi
- Güncel olmayan (>10 dakika) fiyatla yeni işlemleri engelleme

Bu MVP'de **limit emir, kaldıraç, dil modeliyle haber analizi, gerçek mum grafikleri, gerçek zamanlı WebSocket ve çok kullanıcılı yarışma YOKTUR**. Basit adaptif sanal bot ayrı bir özelliktir. Grafik, CoinGecko'nun 7 günlük fiyat serisinden çizilen çizgidir; canlı mum grafiği değildir.

## Tarayıcıdan direkt çalıştır (GitHub Pages)

**Web adresi (yayın etkinleştirildikten sonra):** https://ashina61.github.io/sanal-trader/

GitHub'da bir kez **Settings → Pages → Build and deployment → Source: GitHub Actions** seç. Sonra **Actions → Publish SanalTrader Web → Run workflow**. Yayın tamamlanınca yukarıdaki web adresiyle aç. Sonraki `main` değişiklikleri otomatik olarak yeniden yayınlanır.

İlk web sürümü **sadece sanal TL** kullanır. Firebase varsayılan olarak kapalıdır, portföy bu tarayıcıda saklanır. Fiyatların gelmesi üçüncü taraf API'nin erişilebilirliğine bağlıdır. **GitHub Pages yayını herkese açıktır**, oturum açma veya özel erişim kontrolü yoktur.

Detaylar: [WEB_YAYIN.md](WEB_YAYIN.md).

## Şimdi Codespaces ile geliştiriyoruz (APK gerekmez)

**Başlangıç:** GitHub'da **Code → Codespaces → Create codespace on main**. İlk kurulumdan sonra Codespaces terminalinden:

```bash
bash scripts/start_web.sh
```

**Ports** sekmesinde **3000 → Open in Browser** ile uygulamayı aç. Alternatif olarak VS Code içinden **Terminal → Run Build Task → SanalTrader: Web önizleme** görevini kullan.

Tüm adımlar, sınırlar ve hata çözümleri: **[CODESPACES.md](CODESPACES.md)**.

Her push işleminde yalnızca Flutter web analiz/test/derlemesi kontrol edilir. **Android APK workflow'u otomatik çalışmaz**; ileride istersek GitHub Actions'tan elle başlatabiliriz.

Eski GitHub kurulum notları: [GITHUB_KURULUM.md](GITHUB_KURULUM.md).

## 1. Android'de başlatma (Firebase gerekmiyor)

Bilgisayarında [Flutter SDK](https://docs.flutter.dev/get-started/install) ve Android Studio / Android SDK kurulu olmalı.

Kaynak ZIP'i açıp bu klasörde bir terminal çalıştır:

```bash
flutter doctor
flutter create --platforms=android --org com.example --project-name sanal_trader .
flutter pub get
flutter run
```

Windows'ta alternatif olarak `scripts/start_android.bat` dosyasını çalıştırabilirsin. Linux/macOS'ta `bash scripts/start_android.sh`.

**Neden `flutter create` gerekli?** Bu teslimat Dart/Flutter kaynakları ve testleriyle gelen hafif bir proje şablonudur. Makinede Android'e özel Gradle/SDK dosyalarını kurulu Flutter sürümünle uyumlu olarak `flutter create` üretir.

Release APK'de internet erişimi için `android/app/src/main/AndroidManifest.xml` içinde `<manifest ...>` etiketinin hemen ardından aşağıdaki izni ekle:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Sonra:

```bash
flutter build apk --release
```

APK yolu: `build/app/outputs/flutter-apk/app-release.apk`.

> Bu ortamda Flutter/Android SDK bulunmadığından derleme veya cihaz üzerinde çalıştırma doğrulaması yapılamadı. Kod, doğrudan `flutter create` ile oluşturulan Android projesine eklenmek üzere hazırlanmıştır.

## 2. Firebase'i isteğe bağlı etkinleştir

**Yerel kayıt modu varsayılandır ve Firebase hesabı gerektirmez.** Firebase için:

1. Firebase Console'da proje oluştur.
2. Authentication -> Sign-in method -> **Anonymous** aç.
3. Cloud Firestore veritabanı oluştur; `firebase/firestore.rules` içeriğini Firebase Console > Firestore > Rules bölümüne aktar ve publish et.
4. Firebase CLI / FlutterFire CLI kur ve giriş yap:

```bash
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android
```

5. Android ayarları ve `google-services.json` FlutterFire tarafından üretilir. Ardından:

```bash
flutter run --dart-define=ENABLE_FIREBASE=true
```

Android uygulaması native Firebase config üzerinden `Firebase.initializeApp()` yapar; Firebase ayarları eksikse açık bir hata sayfası gösterir, **kendiliğinden başka kayıt moduna geçmez**.

**Önemli:** Yerel moddan Firebase moduna mevcut işlemleri otomatik taşımıyoruz. Her modun portföyü ayrıdır. Anonim hesap uygulama silinirse veya kimliği kaybolursa eski bulut portföyüne erişim kaybolabilir. Kalıcı oturum/hesap bağlama ileriki sürümün işidir.

**Güvenlik kapsamı:** Firestore kuralları her kullanıcının yalnızca kendi belgelerini okumasını/yazmasını sağlar; para sanal olduğu için kullanıcıların kendi verisini manipüle etmesini önleyen güçlü sunucu doğrulaması bu kişisel prototipte yoktur. Genel kullanıma açmadan önce işlem hesaplarını güvenilir Cloud Functions katmanına taşımak gerekir.

## 3. API ve erişim sınırlaması

Fiyat sağlayıcısı: **CoinGecko** `GET /api/v3/coins/markets?vs_currency=try&ids=...&sparkline=true`.

- Varsayılan olarak API anahtarı olmadan public erişim denenir. CoinGecko bölgesel/rate-limit kuralları nedeniyle **401/403/429** yanıtı verebilir. Böyle olursa uygulama sahte fiyat üretmez; uyarı gösterir ve işlemi açmaz.
- Ücretsiz Demo API anahtarıyla daha güvenilir kullanım için [CoinGecko Demo API](https://www.coingecko.com/en/api) hesabı açılabilir. **API anahtarını APK içine gömme.** Daha sonra Firebase Cloud Functions veya başka sunucu proxy'si üzerinden eklenmeli.
- Fiyatlar gerçek piyasa kaynaklı **gösterge fiyatlarıdır**, emir defteri derinliği veya gecikmesi simüle edilmez; bu nedenle gerçek alım-satım sonucunu birebir temsil etmez.
- Yaklaşık her 90 saniyede fiyat yenilenir. Uygulama arka plana alınırsa yenileme durur. Manuel yenileme ikonu ve aşağı çekerek yenileme vardır.
- 7 günlük grafik, tarihsel fiyatların **çizgi grafiğidir**; mum grafiği değildir.

## 4. Testler

```bash
flutter test
flutter analyze
```

`test/trade_engine_test.dart`: alış, satım, komisyon, bakiyesizlik ve eski fiyatın engellenmesi.

## Proje dizini

```text
sanal_trader_starter/
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── coin_quote.dart
│   │   └── portfolio.dart
│   ├── services/
│   │   ├── market_service.dart
│   │   ├── trade_engine.dart
│   │   ├── portfolio_repository.dart
│   │   ├── local_portfolio_repository.dart
│   │   └── cloud_portfolio_repository.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   └── coin_detail_screen.dart
│   └── widgets/
│       ├── mini_chart.dart
│       └── formatters.dart
├── test/trade_engine_test.dart
├── firebase/firestore.rules
├── scripts/start_android.bat
├── scripts/start_android.sh
└── pubspec.yaml
```

## Planlanan sonraki adımlar

1. Fiyat verisi için sunucu tarafı API proxy, cache ve anahtar yönetimi
2. Kullanıcıya özel limit emir motoru ve iptal edilebilir emir listesi
3. OHLC mum grafikleri, işlem hacmi, indikatörler
4. Komisyon/spread/fiyat kayması ve işlem performansı analizleri
5. Kalıcı Firebase hesabı, cihazlar arası senkronizasyon ve bütçe ayarları

Bu ilk sürüm kişisel ve **yalnızca sanal para** içindir.
