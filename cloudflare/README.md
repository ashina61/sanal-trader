# SanalTrader — ücretsiz harici zamanlayıcı

Bu Cloudflare Worker **sanal işlem yapmaz**. Sadece mevcut
`Free Scheduled Paper Bot` GitHub Actions workflow'unu 5 dakikada bir
`workflow_dispatch` ile tetikler. Fiyat kontrolü, Groq kararı, işlem motoru
ve 650 TL'lik **mevcut** `bot-data/state.json` kasası aynı kalır.

## Kurulum (bir kez)

1. [Cloudflare Workers](https://dash.cloudflare.com/?to=/:account/workers-and-pages)
   hesabını aç. Workers Free planını seç; ücretli plan şart değil.
2. `ashina61/sanal-trader` GitHub deposunu **Workers & Pages → Create → Import a repository**
   ile bağla. Worker adı `sanaltrader-scheduler`, kök klasörü `cloudflare`
   ve deploy komutu `npx wrangler deploy` olarak ayarla (gerekirse Wrangler
   build komutuna `npx wrangler deploy --config cloudflare/wrangler.toml` yaz).
   Projenin adı `wrangler.toml` içindeki isimle eşleşmeli.
   Alternatif: bilgisayarda repo kökünden
   `npx wrangler deploy --config cloudflare/wrangler.toml`.
3. GitHub → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens: **yalnızca bu depo** (`ashina61/sanal-trader`)
   seçili, **Actions: Read and write** izni olan bir token oluştur.
   Mümkünse kısa süreli/son kullanma tarihli token kullan ve süresi dolmadan yenile.
   Bu tokeni kod dosyasına, GitHub deposuna, Flutter'a veya sohbet mesajına yazma.
4. Cloudflare Worker → Settings → Variables and Secrets →
   **Add secret**: adı `GITHUB_DISPATCH_TOKEN`, değeri yukarıdaki token.
   Secret ekledikten sonra gerekirse deploy'u yeniden başlat.
   GitHub Actions tarafındaki `GROQ_API_KEY` orada kalır; Cloudflare'a
   kopyalanmaz.
5. Worker → Settings → Triggers/Cron Triggers altında `*/5 * * * *`
   zamanlamasının göründüğünü ve etkin olduğunu doğrula. İlk tetiklerin
   devreye girmesi birkaç dakika alabilir.
6. Worker'ın `https://sanaltrader-scheduler.<hesabın>.workers.dev/health`
   yolunu aç: `configured: true` olmalı (bu tek başına cronun çalıştığını
   kanıtlamaz). Ardından GitHub Actions → Free Scheduled Paper Bot
   geçmişinde `workflow_dispatch` olayları ve `bot-data/state.json`
   içindeki `lastSuccessAt` zamanının ilerlediğini doğrula.

**Güvenlik:** HTTP üzerinden tetikleme **yoktur**. `/health` yalnızca
konfigürasyonun varlığını gösterir; tokeni açığa çıkarmaz. GitHub
`workflow_dispatch` API yanıtı 204 değilse cron hata verir; sanal
işlem uydurmaz.

**Sınırlar:** Cloudflare ve GitHub'ın ücretsiz planları kota, gecikme ve
kesinti sınırlarına tabidir; yüzde yüz garantili kesintisiz çalışma sözü
verilemez. GitHub'ın kendi `schedule` tetiklemesi yedek kalır. İki
tetik aynı dakikaya denk gelirse workflow concurrency ve sunucu botunun
150 saniyelik tekrarlı kontrol koruması kullanılır.

## Yerel ücretsiz test

`node --test cloudflare/test/worker.test.mjs`

## Groq bağlantısı testi

GitHub → Actions → **Groq AI Connectivity (No Trades)** → **Run workflow**.
Bu kontrol yalnızca Groq'a örnek JSON sorgusu gönderir; piyasa taraması,
yeni emir, `bot-data` okuma/yazma veya kasa sıfırlama yapmaz.
