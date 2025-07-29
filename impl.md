web/を修正して、scripts/verify-bidirectional-swap.tsの実行を、webフロントエンドから実行できるようにする。
ethとsuiのwalletを繋げて、それらのwalletをユーザーwalletとして、sepolia<>suiのsend, receive walletとする。
sendの価格を入力して、固定レートで受け取りwalletでreceiveできる量を確認できて、その後、txを送って、send, inできるようにする。
ethreumのconnect walletはraimbow walletを使う。tx系はviem/wagmiを使う。それ以外は使わない。
ユーザーウォレットのコネクトと、金額入力以外は、全てscripts/verify-bidirectional-swap.tsと全く同じ挙動をするようにする。
resolverなど、他のアクターは.envで環境変数で定義する形で、scriptsと全く同じにする。
デザインもシンプルで最低限で良いので、mvpを実装する。
.envも作成して(scripts/.envと同じ部分が多いと思うが、wallet connectの変数などは後で私が入れるので定義だけして空にしておいて良い)
docs/sui-sdk.mdも参考にして
常にいらないコードは消して、シンプルなコードに保って、可読性を上げることを意識して