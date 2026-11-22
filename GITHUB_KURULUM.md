# SanalTrader'ı GitHub sitesi üzerinden başlatma

> **Güncel tercih: Codespaces/web geliştirme.** Depo hazırdır, yeniden oluşturman veya ZIP yüklemen gerekmez. Doğrudan [CODESPACES.md](CODESPACES.md) ile başlayabilirsin. APK workflow'u sadece manuel çalıştırılır.

## 1. Yeni depo oluştur

1. GitHub hesabında oturum aç: https://github.com/new
2. **Repository name:** `sanal-trader`
3. **Private** seç. (Şimdilik kişisel kullanım.)
4. **Add a README**, **.gitignore** ve **license** kutularını **işaretleme**. Bunlar bu projede zaten var.
5. **Create repository**.

## 2. Dosyaları tarayıcıdan yükle

1. Bu ZIP dosyasını bilgisayarda **ayıkla**.
2. GitHub'da açtığın boş depo ekranındaki **uploading an existing file** bağlantısını aç.
3. Ayıkladığın `sanal_trader_starter` klasörünün **içindeki** dosya ve klasörleri yükle. Ana depo kökünde `pubspec.yaml`, `lib/`, `.github/` görünmeli. ZIP dosyasını tek başına yüklemek *işe yaramaz*.
4. Alttaki **Commit changes** düğmesiyle kaydet.

> GitHub mobil web arayüzünde toplu dosya yükleme zor olabilir. Mümkünse bilgisayarda tarayıcı kullan. Depoyu oluşturduktan sonra depoyu paylaşarak yüklemeyi bağlı GitHub üzerinden ChatGPT'ye de yaptırabilirsin.

## 3. Bilgisayara kurulum yapmadan APK üret

GitHub'da **Actions → SanalTrader Android APK → Run workflow** yolunu izle.

`android-apk.yml` workflow'u:
- Flutter ve Java 17 kurar.
- Eksik Android proje dosyalarını otomatik oluşturur.
- Android internet iznini ekler.
- Dart analizi ve testleri çalıştırır.
- Başarılıysa `app-release.apk` üretir.

Bittiğinde ilgili workflow sayfasındaki **Artifacts** bölümünden `SanalTrader-Android-APK` ZIP dosyasını indir. İçindeki APK'yı Android cihazına kurabilirsin.

**Not:** Bu bir deneme APK'sıdır, Play Store yayın anahtarı kullanılmaz. Firebase varsayılan olarak kapalıdır; yerel sanal cüzdan kullanır. İlk GitHub Actions çalıştırması henüz doğrulanmamıştır, hata çıkarsa Actions loglarından düzeltilmesi gerekir.

## 4. Doğrudan GitHub sitesinde kod yazma

- Küçük düzenlemeler: Depoda herhangi bir dosyayı aç → kalem simgesiyle düzenle → **Commit changes**.
- Tam IDE: Depo ekranında **Code → Codespaces → Create codespace on main**. `.devcontainer/` otomatik olarak Flutter SDK ve web yapılandırmasını kurmaya çalışır.
- Codespaces terminalinde şu komutu çalıştır:

  ```bash
  flutter run -d web-server --web-hostname 0.0.0.0 --web-port 3000
  ```

- **Ports** sekmesinde 3000 portunu açıp web önizlemeye girebilirsin. Bu web önizleme geliştirme içindir; CoinGecko API bazı tarayıcı erişimlerinde CORS/rate-limit nedeniyle engellenebilir. Android hedef sürüm ayrı olarak GitHub Actions ile üretilir.

## 5. Proje yapısı

- `lib/`: Flutter ekranları, sanal işlem motoru ve piyasa servisi
- `test/`: işlem motoru testleri
- `firebase/`: isteğe bağlı Firestore kuralları
- `.github/workflows/`: GitHub üzerinden otomatik Android APK derleme
- `.devcontainer/`: GitHub Codespaces web editörü kurulumu

**Güvenlik:** GitHub'a API anahtarı, token, Firebase servis hesabı JSON'u, Android keystore, özel parola ekleme. Bu depo kişisel simülasyondur, gerçek alım-satım yapmaz.
