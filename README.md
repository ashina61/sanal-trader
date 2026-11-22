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
- **Yeni kurulumlarda yerel sanal bot kapalı başlar.** Bot sekmesindeki anahtarla bilerek etkinleştirebilirsin; daha önce kaydedilmiş açık/kapalı tercihin ve işlemlerin korunur. Bu anahtar sunucu botunu yönetmez.
- Uygulama açıkken bot 45 saniyelik döngülerle yeni piyasa fırsatlarını değerlendirir. Her döngüde **en fazla bir sanal emir** verebilir; işlem yoksa sinyal ve risk sınırları beklenir.
- Fiyatlar **canlı işlem garantisi değildir**; WebSocket bağlantısı kopabilir, piyasa verileri engellenebilir. Sitede **CANLI** veya yedek kaynak durumu gösterilir.
- GitHub Pages yalnızca web arayüzüdür. **Yerel bot tarayıcı kapanınca durur; ayrı ücretsiz GitHub Actions sanal botu ise planlandığında tarayıcıdan bağımsız çalışır.** GitHub planlaması gecikebilir/atlanabilir; sürekli açık sunucu garantisi değildir.

## Sitede öğrenen bot (sanal işlemler)

**Web:** https://ashina61.github.io/sanal-trader/

Ana sayfada **Bot** sekmesine gir, riskleri oku ve **Botu aç** anahtarını etkinleştir. Bot başlangıçta **kapalıdır**. Açıkken güncel veriler üzerinden kendi başına **sanal** alım/satım yapar ve yaptığı işlemlerin nedenini bot günlüğüne ekler.

- Üç fiyat uzmanının (kısa trend, 24s momentum, ters yön) ağırlıkları en az 15 dakika sonra gelen **yeni fiyatlarla** değerlendirilerek güncellenir. Bu, basit bir **online öğrenme algoritmasıdır**, büyük dil modeli veya kâr garantisi değildir.
- En fazla toplam portföyün %12'si kadar yeni alış; tek coinde %25; toplam coinlerde %65; en az %30 sanal nakit rezervi.
- Günlük en fazla 8 emir; aynı coinde 30 dakika tekrar bekleme (koruyucu satış hariç); yaklaşık %6 zarar koruması ve %8 kâr alma.
- Yerel bot açık sekmede yaklaşık 45 saniyede bir karar vermeyi dener. WebSocket bağlantısı koparsa REST yenilemesi yaklaşık iki dakika aralıklarla denenir; tarayıcı kapanınca **yalnızca yerel bot durur**.
- Botun ayarları ve öğrenme sayıları tarayıcıdaki yerel depolamada tutulur. Site verilerini temizlersen silinebilir.
- Bot ve sen manuel sanal alım/satım için aynı doğrulama motorunu kullanırsınız. **Gerçek borsa bağlantısı, anahtar, para transferi bulunmaz**.

Ayrıntılı rehber: **[BOT_REHBERI.md](BOT_REHBERI.md)**.

### Otonom işlem kararları (v0.9.2)

Sunucu botu uygun fiyata ve açık pozisyona göre **spot AL / LONG**, **spot SAT / LONG kapat**, **1x sanal SHORT aç**, **SHORT kapat** veya **BEKLE** seçer. Bot kendi kendine yeni pozisyon açıp kapatabilir; kullanıcıdan her işlem için onay istemez. Güçlü ve taze teknik veri yoksa, nakit/maruziyet riski yüksekse veya maliyet payını karşılamayan sinyal varsa **BEKLE** seçer.

**Bot → Sunucu Botu → Otonom Karar Merkezi** bölümünde son piyasa rejimi, karar, işlem gerekçesi, seçilen coin ve ilk beş güçlü aday görünür. Bu kararlar GitHub Actions çalıştığında yenilenir; sürekli saniyelik analiz veya gerçek borsa emirleri değildir. Spot AL ile LONG aynı yönlü pozisyondur; sunucuda ayrı kaldıraçlı LONG kontratı yoktur. SHORT ayrı 1x sanal teminat kullanır.

## Ücretsiz sunucu botu · v0.9.2

**Çalışan sunucu simülasyonu:** GitHub Actions üzerinde yaklaşık her beş dakikada bir planlanan Python motoru, yalnızca herkese açık Binance spot verileriyle **1x sanal LONG/SHORT** alım ve kapatmalarını değerlendirebilir. Sonuçları herkese açık `bot-data/state.json` dalında saklar. GitHub zamanlayıcısı gecikebilir veya işlemi atlayabilir; bu VPS gibi kesintisiz gerçek zamanlı bot değildir.

**Sayfa bağlantıları:** Panel ve Portföy sunucu kasasının özetini, Bot açık pozisyonları ve teknik günlük durumunu, Kâr ise ayrı sunucu performansını gösterir. **Sunucu işlem geçmişi** ayrıca açılır; tarayıcıdaki yerel işlem geçmişinden farklıdır. Yeni sanal sunucu hesabının başlangıcı ₺650; eski yerel tarayıcı hesabı da ayrı ₺650 başlayabilir. Bu iki hesabın toplamı **bir tek 1.300 TL yatırım portföyü değildir**. İşlemleri/bakiyeleri otomatik birleştirmiyoruz.

**Yönetim:** Web uygulamasındaki yerel bot anahtarı sunucu botunu kontrol etmez; sunucu botu Actions menüsünden `run`, `pause`, `resume` ile yönetilir. `reset` yalnızca ayrı sunucu sanal cüzdanını sıfırlar.

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

**Sınır:** Tarayıcı kapalıyken **yerel bot durur**. Sunucu botu bağımsız zamanlanan GitHub işleriyle kendi ayrı sanal hesabını izlemeyi sürdürebilir; gecikmeler mümkündür.

## Mevcut kapsam ve dürüst sınırlar

- **Panel · Radar · Portföy · Bot · Kâr**: Canlı fiyat ve teknik analiz, sanal emir, durum/karar geçmişi, gerçekleşmiş sanal net sonuç ve karşılaştırmalı testler.
- **Tarayıcıdaki yerel kasa**: Varsayılan depolama `shared_preferences`; manuel spot AL/SAT ve istenirse yerel otomatik bot. İşlemler aynı sekmede sıraya alınır, eşzamanlı yazma riski azaltılır. Farklı cihazlar otomatik eşleşmez.
- **Sunucudaki ayrı kasa**: Ücretsiz GitHub Actions periyodik botu, `bot-data` dalında kalıcı sanal işlemler; LONG/SHORT 1x, varsayımsal komisyon, stop/teminat ve maruziyet kuralları. Tarayıcıdan salt okunur.
- **Fiyat kaynağı**: Öncelikle Binance REST + `!miniTicker@arr` WebSocket ve USDT/TRY dönüşümü; erişim sorunu varsa CoinGecko TRY fiyatı yedeği. Geçmiş TRY mumları aynı anın kuruyla çevrildiğinden gerçek tarihsel TRY OHLC değildir.
- **Sınırlamalar**: Ücretsiz cron sürekli saniyelik izleme değildir, duraklayabilir; stop fiyatı garanti edilmez. SHORT funding/faiz, gerçek emir defteri, spread ve likidasyon kademeleri tam modellenmez. Kâr veya gerçek borsa getirisi garanti edilmez.


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

Birincil fiyat sağlayıcısı: **Binance public REST** ve public **WebSocket**. Yedek sağlayıcı **CoinGecko** `GET /api/v3/coins/markets?vs_currency=try&...`.

- Varsayılan olarak API anahtarı olmadan public erişim denenir. CoinGecko bölgesel/rate-limit kuralları nedeniyle **401/403/429** yanıtı verebilir. Böyle olursa uygulama sahte fiyat üretmez; uyarı gösterir ve işlemi açmaz.
- Ücretsiz Demo API anahtarıyla daha güvenilir kullanım için [CoinGecko Demo API](https://www.coingecko.com/en/api) hesabı açılabilir. **API anahtarını APK içine gömme.** Daha sonra Firebase Cloud Functions veya başka sunucu proxy'si üzerinden eklenmeli.
- Fiyatlar gerçek piyasa kaynaklı **gösterge fiyatlarıdır**, emir defteri derinliği veya gecikmesi simüle edilmez; bu nedenle gerçek alım-satım sonucunu birebir temsil etmez.
- Tarayıcı açıkken WebSocket veri akışı kullanılır; kesintide yaklaşık iki dakikalık REST kontrolleri denenir. Manuel yenileme ve aşağı çekerek yenileme vardır. Bağımsız sunucu botu ayrı zamanlanır.
- Radar ve detayda geçmiş çizgi grafiği, yeterli veride tamamlanan saatlik Binance mumlarıyla teknik analiz vardır; tarihsel TRY kuruyla ayrı ayrı dönüştürülmüş OHLC değildir.

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
