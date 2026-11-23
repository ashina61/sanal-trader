# v0.9.26 — DEX sözleşme uyarıları, maliyet stres testi ve kapanmış işlem analizi

Bu paket videodaki SCANNER / RUG CHECK / SIZER / EXECUTOR / LOGGER / EQUITY
iş bölümünü mevcut tek sanal kasayla ilişkilendirir. Videonun getiri
iddialarını doğrulanmış varsaymaz.

## DEX sözleşme güvenliği

GeckoTerminal'den izlenen en fazla dört Solana/Base tokeni için GoPlus
Token Security kamu API'si sorgulanır; ücretli anahtar gerekmeden
çalışmayı dener. Base: chain 8453. Solana: beta endpoint. Resmî kaynaklar:

https://docs.gopluslabs.io/reference/tokensecurityusingget_1
https://docs.gopluslabs.io/reference/solanatokensecurityusingget
https://docs.gopluslabs.io/reference/support

Honeypot, mint yetkisi, blacklist, transfer durdurma, proxy, değişebilir
vergi ve yüksek alış/satış vergisi gibi *bildirilmiş* alanlar işaretlenir.
Solana'da yalnız açıkça tanınan yetki alanları incelenir. Bilgi yoksa
UNKNOWN, servis hata verirse UNAVAILABLE. PARTIAL güvenli demek değildir.
LP kilidi, bağımsız sahiplik, gerçek satış testleri veya garanti yoktur.
Hiçbir DEX sinyali emir oluşturmaz.

## Emir defteri maliyeti

Mevcut Binance public depth20 tahmini, ilk kademenin baz miktarıyla değil
tam işlem **USDT bütçesi** ile her kademede ilerler. Bu gerçek dolum
değil, anlık gözlenmiş kamu emir defteri üzerindeki senaryodur.

Net kasa muhasebesi ve geçmiş değişmedi. Açık pozisyonları 5 baz puan
daha kötü fiyatta kapatmayı varsayan ayrı bir stres senaryosu eklenir:
objective.scenarioNetAfterSlippageTry. Gerçek kayma değişebilir.
Gerçekleşmiş işlem ücretleri bu stres hesabında tekrar düşülmez.

## Son işlem öğrenme raporu

Tek kasadaki son en fazla 100 emir kaydının kapanan SPOT SAT ve
SHORT KAPAT sonuçları okunur. Son 10 kapanışın net sonucu, kayıp serisi,
SPOT/SHORT performansı, net kâr/zarar faktörü ve çıkış türleri incelenir.
Bu gözlem katmanı geçmiş kayıtları değiştirmez. Sonuçlar mevcut
sinyal öğrenme ve risk frenlerine ek rapordur; otomatik yeni işlem
yetkisi değildir. 100 emir sınırı tüm geçmiş istatistiği değildir.

## Mobil

Radar > Ücretsiz DEX keşfi > Token sözleşmesi başlığında risk kayıtları
gösterilir. Bot ve Kâr sayfalarına kısa öğrenme ve 5 baz puan ekstra
kayma senaryosu eklenir. Tek sanal kasa ve koruyucu çıkışlar korunur.

## Kontrol

python3 -m unittest discover -s backend/tests -v
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test

GitHub cron saniyelik stop izlemesi değildir; kamu API erişimi garantili
değildir. Bu paket kâr garantisi vermez.
