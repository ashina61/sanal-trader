# SanalTrader — GitHub Codespaces ile web geliştirme

Bu depoda **Android APK üretmeden** Flutter uygulamasını tarayıcıda çalıştırıp geliştirebilirsin. İlk sürüm kişisel kullanımdır: **650 TL tamamen sanal başlangıç bakiyesi**, kripto TRY fiyatları ve sanal AL/SAT.

## 1) Codespaces'i aç

1. [ashina61/sanal-trader](https://github.com/ashina61/sanal-trader) deposunu aç.
2. **Code → Codespaces → Create codespace on main**.
3. Web tabanlı VS Code açılır. `.devcontainer/devcontainer.json` ilk kurulumda Flutter SDK, web desteği ve bağımlılıkları kurar. Kurulum tamamlanmadan terminal komutunu başlatma.

> Codespaces bulut ortamıdır, işlem süresi ve kota sınırları GitHub planına bağlı olabilir.

## 2) Uygulamayı tarayıcıda göster

Codespaces içinde **Terminal → New Terminal**:

```bash
bash scripts/start_web.sh
```

Alternatif: **Terminal → Run Build Task → SanalTrader: Web önizleme**.

**Ports** sekmesi → **3000** → **Open in Browser**. Portun görünürlüğü **Private** olarak kalsın. Önizleme adresi Codespaces'e özeldir ve tarayıcı üzerinden açılır.

Önizleme, `--dart-define=ENABLE_FIREBASE=true` kullanılmadığından **yerel portföy** modunda çalışır; Firebase hesabı/anahtarı gerektirmez. Uygulama, tarayıcıda ve önizleme adresinde saklanan verileri kullanır; farklı tarayıcı veya yeni önizleme adresi aynı portföyü paylaşmayabilir.

## 3) Kod düzenle, test et, kaydet

Uygulama ekranları `lib/screens/`, fiyat verileri `lib/services/market_service.dart`, sanal işlem mantığı `lib/services/trade_engine.dart` içinde.

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

Düzenlemeyi gördüğün terminalde `r` ile hot reload, `R` ile hot restart (destekleniyorsa). Gerekirse işlemi durdurup `bash scripts/start_web.sh` ile yeniden başlat. Kodların GitHub'da kalıcı olması için VS Code **Source Control** sekmesinden **Commit** ve **Sync/Push** işlemlerini yap.

```bash
git status
git add .
git commit -m "Improve web preview"
git push
```

> `git add .` öncesinde yeni oluşturulan dosyaları kontrol et; gizli anahtar, token, keystore veya kişisel verileri GitHub'a koyma.

## 4) Bilinen sınırlar ve hata kontrolü

- CoinGecko piyasa API'si internet ve istek limitine bağlıdır. 401/403/429 yanıtında sahte fiyat gösterilmez; API hatası görünür.
- `flutter: command not found`: terminali yeniden aç veya `bash scripts/codespaces_setup.sh` çalıştır. İlk kurulum Flutter SDK'yi `$HOME/flutter` altına kurar.
- 3000 portu yok: terminaldeki web komutunun hâlâ çalıştığına ve hata vermediğine bak.
- Tarayıcıdan web önizleme test ortamıdır; Android tasarımı ayrı cihazda daha sonra doğrulanacaktır.
- GitHub Actions **SanalTrader Web Checks**: her push'ta analiz, test ve web derlemesini kontrol eder. **Android APK** yalnızca elle başlatılabilir.
- Bu sürümde gerçek borsa emri, para yatırma, kaldıraç ve limit emirleri bulunmaz.

## 5) Sıradaki geliştirme hedefi

Web önizlemeyi açıp piyasa/portföy ekranlarını doğrulamak → hataları gidermek → daha gelişmiş grafikler ve sanal emir kontrolleri eklemek.
