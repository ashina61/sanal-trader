# SanalTrader — Flutter + Firebase Android MVP

Gerçek kripto piyasası TRY fiyatlarını **sadece sanal ₺650** başlangıç bakiyesiyle alıp satmak için Android öncelikli örnek uygulama.

> **Hiçbir yerde gerçek emir, borsa hesabı, para yatırma, para çekme veya cüzdan anahtarı yoktur.** Bu uygulama bir paper-trading simülatörüdür; yatırım tavsiyesi değildir.

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

Bu MVP'de **limit emir, kaldıraç, haber/AI analizi, gerçek mum grafikleri, gerçek zamanlı WebSocket ve çok kullanıcılı yarışma YOKTUR**. Grafik, CoinGecko'nun 7 günlük fiyat serisinden çizilen çizgidir; canlı mum grafiği değildir.

## GitHub üzerinden geliştirme (bilgisayarda kurulum zorunlu değil)

Bu proje GitHub sitesinden düzenleme ve otomatik APK oluşturma için hazırlanmıştır. Yeni depo açma, dosyaları yükleme, GitHub Actions ile APK alma ve Codespaces web önizlemesi adımları: **[GITHUB_KURULUM.md](GITHUB_KURULUM.md)**.

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