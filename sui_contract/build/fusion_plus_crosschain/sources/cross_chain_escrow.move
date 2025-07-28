module fusion_plus_crosschain::cross_chain_escrow {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::event;
    use std::string::String;
    use fusion_plus_crosschain::hash_lock;
    use fusion_plus_crosschain::time_lock;

    /// エラーコード
    const E_INVALID_TIME_LOCK: u64 = 1;
    const E_INVALID_AMOUNT: u64 = 2;
    const E_NOT_TAKER: u64 = 3;
    const E_ALREADY_FILLED: u64 = 4;
    const E_EXPIRED: u64 = 5;
    const E_INVALID_SECRET: u64 = 6;
    const E_NOT_MAKER: u64 = 7;
    const E_NOT_EXPIRED: u64 = 8;
    const E_SECRET_ALREADY_USED: u64 = 9;
    const E_INSUFFICIENT_REMAINING_AMOUNT: u64 = 10;
    const E_INVALID_FILL_AMOUNT: u64 = 11;

    /// 使用済みシークレット管理用のグローバル構造体
    public struct UsedSecretsRegistry has key {
        id: sui::object::UID,
        used_secrets: vector<vector<u8>>,
    }

    /// 初期化関数
    fun init(ctx: &mut sui::tx_context::TxContext) {
        let registry = UsedSecretsRegistry {
            id: sui::object::new(ctx),
            used_secrets: std::vector::empty(),
        };
        sui::transfer::share_object(registry);
    }

    /// テスト用初期化関数
    #[test_only]
    public fun init_for_testing(ctx: &mut sui::tx_context::TxContext) {
        init(ctx);
    }

    /// クロスチェーンエスクロー構造体
    public struct CrossChainEscrow<phantom T> has key, store {
        id: sui::object::UID,
        maker: address,
        taker: address, // address(0x0)の場合は誰でもfill可能
        total_amount: u64,
        remaining_amount: u64,
        balance: Balance<T>,
        hash_lock: vector<u8>,
        time_lock: u64,
        is_filled: bool,
        created_at: u64,
        ethereum_order_hash: String,
        secret: vector<u8>, // シークレットが明かされた後に保存
    }

    /// イベント構造体
    public struct EscrowCreated has copy, drop {
        escrow_id: sui::object::ID,
        maker: address,
        taker: address,
        amount: u64,
        hash_lock: vector<u8>,
        time_lock: u64,
        ethereum_order_hash: String,
    }

    public struct EscrowPartiallyFilled has copy, drop {
        escrow_id: sui::object::ID,
        resolver: address,
        amount: u64,
        remaining_amount: u64,
        secret: vector<u8>,
        ethereum_order_hash: String,
    }
    
    public struct EscrowFilled has copy, drop {
        escrow_id: sui::object::ID,
        last_resolver: address,
        secret: vector<u8>,
        ethereum_order_hash: String,
    }

    public struct EscrowCancelled has copy, drop {
        escrow_id: sui::object::ID,
        maker: address,
        ethereum_order_hash: String,
    }

    public struct EscrowRefunded has copy, drop {
        escrow_id: sui::object::ID,
        maker: address,
        amount: u64,
        ethereum_order_hash: String,
    }

    /// エスクローを作成
    public fun create_escrow<T>(
        coin: Coin<T>,
        taker: address,
        hash_lock: vector<u8>,
        time_lock: u64,
        ethereum_order_hash: String,
        clock: &Clock,
        ctx: &mut sui::tx_context::TxContext
    ): CrossChainEscrow<T> {
        let amount = coin::value(&coin);
        let maker = sui::tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(time_lock::is_valid_time_lock(time_lock, clock), E_INVALID_TIME_LOCK);
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        let escrow_uid = sui::object::new(ctx);
        let escrow_id = sui::object::uid_to_inner(&escrow_uid);
        
        let escrow = CrossChainEscrow<T> {
            id: escrow_uid,
            maker,
            taker,
            total_amount: amount,
            remaining_amount: amount,
            balance: coin::into_balance(coin),
            hash_lock,
            time_lock,
            is_filled: false,
            created_at: current_time,
            ethereum_order_hash,
            secret: std::vector::empty(),
        };

        event::emit(EscrowCreated {
            escrow_id,
            maker,
            taker,
            amount,
            hash_lock,
            time_lock,
            ethereum_order_hash,
        });

        escrow
    }

    /// エスクローを作成して共有
    public fun create_and_share_escrow<T>(
        coin: Coin<T>,
        taker: address,
        hash_lock: vector<u8>,
        time_lock: u64,
        ethereum_order_hash: String,
        clock: &Clock,
        ctx: &mut sui::tx_context::TxContext
    ): object::ID {
        let amount = coin::value(&coin);
        let maker = sui::tx_context::sender(ctx);
        let current_time = clock::timestamp_ms(clock);
        
        assert!(time_lock::is_valid_time_lock(time_lock, clock), E_INVALID_TIME_LOCK);
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        let escrow_uid = sui::object::new(ctx);
        let escrow_id = sui::object::uid_to_inner(&escrow_uid);
        
        let escrow = CrossChainEscrow<T> {
            id: escrow_uid,
            maker,
            taker,
            total_amount: amount,
            remaining_amount: amount,
            balance: coin::into_balance(coin),
            hash_lock,
            time_lock,
            is_filled: false,
            created_at: current_time,
            ethereum_order_hash,
            secret: std::vector::empty(),
        };

        event::emit(EscrowCreated {
            escrow_id,
            maker,
            taker,
            amount,
            hash_lock,
            time_lock,
            ethereum_order_hash,
        });

        // 共有オブジェクトとして共有
        sui::transfer::share_object(escrow);
        
        // IDを返す
        escrow_id
    }

    /// エスクローを共有オブジェクトとして共有
    public fun share_escrow<T>(escrow: CrossChainEscrow<T>) {
        sui::transfer::share_object(escrow);
    }


    /// エスクローを部分的にフィル（指定した分のみ受け取り）
    public fun fill_escrow_partial<T>(
        escrow: &mut CrossChainEscrow<T>,
        registry: &mut UsedSecretsRegistry,
        amount: u64,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut sui::tx_context::TxContext
    ): Coin<T> {
        let sender = sui::tx_context::sender(ctx);
        let _current_time = clock::timestamp_ms(clock);
        
        // takerが指定されている場合はtakerのみ、address(0x0)の場合は誰でも可
        if (escrow.taker != @0x0) {
            assert!(sender == escrow.taker, E_NOT_TAKER);
        };
        assert!(!escrow.is_filled, E_ALREADY_FILLED);
        assert!(!time_lock::is_expired(escrow.time_lock, clock), E_EXPIRED);
        assert!(hash_lock::verify_secret(secret, escrow.hash_lock), E_INVALID_SECRET);
        // 初回フィル以外では、同じエスクローで同じシークレットの再利用を許可
        if (!std::vector::is_empty(&escrow.secret)) {
            assert!(escrow.secret == secret, E_INVALID_SECRET);
        } else {
            assert!(!is_secret_used(registry, &secret), E_SECRET_ALREADY_USED);
        };
        assert!(amount > 0, E_INVALID_FILL_AMOUNT);
        assert!(amount <= escrow.remaining_amount, E_INSUFFICIENT_REMAINING_AMOUNT);
        
        // 残量を更新
        escrow.remaining_amount = escrow.remaining_amount - amount;
        
        // 初回フィル時にシークレットを保存
        if (std::vector::is_empty(&escrow.secret)) {
            escrow.secret = secret;
            std::vector::push_back(&mut registry.used_secrets, secret);
        };
        
        // 完了チェック
        let is_completed = escrow.remaining_amount == 0;
        if (is_completed) {
            escrow.is_filled = true;
        };
        
        // 指定した分のみ引き出す
        let coin = coin::from_balance(balance::split(&mut escrow.balance, amount), ctx);
        
        if (is_completed) {
            event::emit(EscrowFilled {
                escrow_id: sui::object::uid_to_inner(&escrow.id),
                last_resolver: sender,
                secret,
                ethereum_order_hash: escrow.ethereum_order_hash,
            });
        } else {
            event::emit(EscrowPartiallyFilled {
                escrow_id: sui::object::uid_to_inner(&escrow.id),
                resolver: sender,
                amount,
                remaining_amount: escrow.remaining_amount,
                secret,
                ethereum_order_hash: escrow.ethereum_order_hash,
            });
        };

        coin
    }
    
    /// エスクローをフィル（残り全額を受け取り）
    public fun fill_escrow<T>(
        escrow: &mut CrossChainEscrow<T>,
        registry: &mut UsedSecretsRegistry,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut sui::tx_context::TxContext
    ): Coin<T> {
        assert!(escrow.remaining_amount > 0, E_ALREADY_FILLED);
        
        // 残り全額でフィル
        let remaining_amount = escrow.remaining_amount;
        fill_escrow_partial(escrow, registry, remaining_amount, secret, clock, ctx)
    }

    /// エスクローをキャンセル（期限切れ後、作成者が資金を回収）
    public fun cancel_escrow<T>(
        escrow: &mut CrossChainEscrow<T>,
        clock: &Clock,
        ctx: &mut sui::tx_context::TxContext
    ): Coin<T> {
        let sender = sui::tx_context::sender(ctx);
        let _current_time = clock::timestamp_ms(clock);
        
        assert!(sender == escrow.maker, E_NOT_MAKER);
        assert!(!escrow.is_filled, E_ALREADY_FILLED);
        assert!(time_lock::is_expired(escrow.time_lock, clock), E_NOT_EXPIRED);
        
        let amount = escrow.remaining_amount;
        let coin = coin::from_balance(balance::withdraw_all(&mut escrow.balance), ctx);
        
        event::emit(EscrowRefunded {
            escrow_id: sui::object::uid_to_inner(&escrow.id),
            maker: sender,
            amount,
            ethereum_order_hash: escrow.ethereum_order_hash,
        });

        coin
    }

    /// シークレットとハッシュロックの検証
    public fun verify_secret(
        secret: vector<u8>,
        hash_lock: vector<u8>
    ): bool {
        hash_lock::verify_secret(secret, hash_lock)
    }

    /// ハッシュロックを作成
    public fun create_hash_lock(secret: vector<u8>): vector<u8> {
        hash_lock::create_hash_lock(secret)
    }

    /// エスクロー情報の取得
    public fun get_escrow_info<T>(escrow: &CrossChainEscrow<T>): (
        address, address, u64, u64, vector<u8>, u64, bool, u64, String
    ) {
        (
            escrow.maker,
            escrow.taker,
            escrow.total_amount,
            escrow.remaining_amount,
            escrow.hash_lock,
            escrow.time_lock,
            escrow.is_filled,
            escrow.created_at,
            escrow.ethereum_order_hash
        )
    }
    
    /// 残り額を取得
    public fun get_remaining_amount<T>(escrow: &CrossChainEscrow<T>): u64 {
        escrow.remaining_amount
    }

    /// エスクローの期限切れ確認
    public fun is_expired<T>(escrow: &CrossChainEscrow<T>, clock: &Clock): bool {
        time_lock::is_expired(escrow.time_lock, clock)
    }

    /// エスクローがフィル可能か確認
    public fun can_fill<T>(escrow: &CrossChainEscrow<T>, clock: &Clock): bool {
        !escrow.is_filled && time_lock::is_active(escrow.time_lock, clock)
    }

    /// 明かされたシークレットを取得
    public fun get_secret<T>(escrow: &CrossChainEscrow<T>): vector<u8> {
        escrow.secret
    }


    /// 使用済みシークレットかどうかを確認
    public fun is_secret_used(registry: &UsedSecretsRegistry, secret: &vector<u8>): bool {
        let mut i = 0;
        let len = std::vector::length(&registry.used_secrets);
        while (i < len) {
            let used_secret = std::vector::borrow(&registry.used_secrets, i);
            if (used_secret == secret) {
                return true
            };
            i = i + 1;
        };
        false
    }

    /// レジストリ内の使用済みシークレット数を取得
    public fun get_used_secrets_count(registry: &UsedSecretsRegistry): u64 {
        std::vector::length(&registry.used_secrets)
    }

    /// バッチでシークレットを作成（テスト用）
    public fun create_batch_hash_locks(secrets: vector<vector<u8>>): vector<vector<u8>> {
        hash_lock::create_batch_hash_locks(secrets)
    }
}