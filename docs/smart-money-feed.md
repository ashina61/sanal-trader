# Akıllı Para / Smart Wallet Radar — v0.9.22

Bu özellik mevcut tek 650 TL sanal kasaya dokunmadan Solana ve Base
akıllı cüzdan kümelerini araştırır. DEX tokenleri Binance USDT paritesi gibi
işlem görmez. Canlı/kesintisiz WebSocket takibi veya garantili stop emri değildir.

## Kaynak kurulumu

Bir zincir üstü veri sağlayıcısının veya kendi indeksleyicinizin HTTPS JSON
adresini GitHub Actions secret olarak SMART_WALLET_FEED_URL adıyla girin.
URL hiç verilmediyse Radar NOT_CONFIGURED gösterir; gerçek cüzdan verisi veya
sinyal varmış gibi davranmaz. Kaynak adresini koda yazmayın.

Sağlayıcının JSON nesnesi:
- asOf: ISO-8601 UTC zaman damgası, en fazla beş dakika eski
- wallets: her öğede chain (solana/base), address, ownerGroup, profit30dUsd,
  winRate30dPct (0–100 arası yüzde), performanceAsOf (UTC),
  performanceVerified: true ve independenceVerified: true
- events: her öğede chain, wallet, tokenAddress, symbol, txHash,
  side (BUY/SELL), at (UTC), verifiedSwap: true, transferOnly: false
- BUY olaylarında ayrıca newCapitalVerified: true, fundingGroup ve
  safety nesnesi zorunlu
- safety: liquidityUsd (en az 200000), priceChange60mPct (en fazla 30),
  lpLocked: true, sellable: true. Solana için mintAuthorityRevoked: true
  ve freezeAuthorityRevoked: true; Base için contractSafetyVerified: true,
  contractMintDisabled: true ve blacklistDisabled: true zorunlu

Solana adresleri base58, Base adresleri EVM 0x-heksadesimal biçimindedir.
Tokenler chain + tokenAddress birleşimiyle tanınır; isimler kimlik değildir.

## Karar koşulları

En yüksek 30 günlük raporlanmış kâra göre en fazla 15 uygun cüzdan kullanılır.
Cüzdan en az %65 kazanma oranı ve 750.000 dolardan FAZLA 30 günlük
raporlanmış kâr taşımalıdır. Performans belgesi en fazla 24 saat eskidir.
Aynı tokeni son 20 dakika içinde, farklı 3+ cüzdan, farklı sahip grubu ve
farklı fonlama grubu almış olmalı. İşlem benzersiz txHash ile sayılır.
Taze para veya swap teyidi olmayan bildirimler, havuzu küçük tokenler,
kilitsiz LP, açık mint/freeze/blacklist hakları ve son saatte %30 üstü
yükselmiş tokenler reddedilir.

Sistem bir token için yalnız bir kez yeni BUY_CLUSTER kaydeder. Ardından
takip edilen cüzdanın gerçek satış bildirimi SMART_WALLET_SELL uyarısı
oluşturabilir. Geçmiş son 24 saatle sınırlıdır. Bu özellik salt-okunur
araştırma ve uyarıdır. %7 pozisyon sınırı, %-7 stop ve onay koşulları
gelecekte gerçekçi DEX fiyat/işlem simülasyonu eklenirse kullanılmak üzere
politikada kayıtlıdır; şu anda otomatik sanal/gerçek DEX alımı yoktur.

## Veriye güven sınırı

Kaynakta performanceVerified, verifiedSwap, newCapitalVerified, LP ve
kontrat kontrolü gibi alanlar indeksleme sağlayıcısının beyanıdır. Modül
bunları Solana/Base RPC üzerinden bağımsız doğrulamaz. Doğruluğu sağlayıcı
tarafından gerçekten denetlenmiş bir indeksleyici gerekir. Grok promptu
tek başına bu veri beslemesini üretmez. Sinyal sonucu kâr garantisi değildir.

Test: python3 -m unittest discover -s backend/tests -v
Alan: bot-data/state.json dosyasında smartMoney. Radar son kontrol saatini,
izlenen cüzdan sayısını, yeni sinyalleri ve satış uyarılarını gösterir.
