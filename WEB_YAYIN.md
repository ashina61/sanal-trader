# SanalTrader'ı doğrudan tarayıcıda açma

Uygulama linki (**GitHub Pages yayını etkinleştirildikten sonra**):

**https://ashina61.github.io/sanal-trader/**

## Bir kez yapılacak GitHub Pages ayarı

1. [GitHub → sanal-trader → Settings → Pages](https://github.com/ashina61/sanal-trader/settings/pages) bölümünü aç.
2. **Build and deployment** altında **Source → GitHub Actions** seç.
3. [Actions → Publish SanalTrader Web](https://github.com/ashina61/sanal-trader/actions/workflows/deploy-web.yml) sayfasını aç.
4. **Run workflow → Branch: main → Run workflow** seç.
5. Workflow **yeşil (success)** olunca üstteki site linkini aç.

Sonraki `main` değişikliklerinde yayın otomatik yenilenir. Codespaces veya APK gerekmiyor; yalnızca yayınlanacak kod üzerinde çalışmak için kullanabilirsin.

### Önemli notlar

- Bu yayın herkesin erişebileceği **public demo** olur. Kişisel/özel erişim gerekiyorsa Pages yerine kimlik doğrulamalı hosting gerekir.
- **Gerçek para kullanılmaz.** 650 TL yalnızca sanal başlangıç bakiyesidir.
- İlk sürümde Firebase kapalıdır. Portföy cihazlar arasında senkronize edilmez; kullandığın tarayıcının yerel verilerine bağlıdır. Site verilerini temizlemek portföyü sıfırlayabilir.
- CoinGecko piyasa verisi üçüncü taraf API üzerinden gelir. API limitleri veya tarayıcı erişim kısıtları sebebiyle fiyatlar gelmeyebilir; sahte fiyat üzerinden işlem yapılmaz.
- İlk kez Pages etkinleştirilmeden çalışmış bir workflow başarısız olabilir; ayar sonrası `Run workflow` ile tekrar çalıştır.
- Çalışma adresi `/sanal-trader/` alt yolunda olduğu için web derlemesi `--base-href /sanal-trader/` ile yapılır.
