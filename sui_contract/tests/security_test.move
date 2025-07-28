#[test_only]
module fusion_plus_crosschain::security_test {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self};
    use sui::clock::{Self};
    use sui::sui::SUI;
    use sui::test_utils::assert_eq;
    use std::string;
    use sui::hash;
    use fusion_plus_crosschain::cross_chain_escrow::{
        Self as escrow, CrossChainEscrow, UsedSecretsRegistry,
        E_NOT_TAKER, E_ALREADY_FILLED, E_EXPIRED, E_INVALID_SECRET, E_NOT_MAKER, E_NOT_EXPIRED, E_SECRET_ALREADY_USED
    };

    // Test constants
    const MAKER: address = @0xA;
    const TAKER: address = @0xB;
    const MALICIOUS_USER: address = @0xC;
    const AMOUNT: u64 = 1000;
    const ONE_HOUR_MS: u64 = 3600000;

    #[test]
    #[expected_failure(abort_code = E_NOT_TAKER)]
    fun test_fill_escrow_wrong_taker() {
        let mut scenario = test::begin(MAKER);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        escrow::share_escrow(escrow);
        
        // Malicious user tries to fill the escrow
        next_tx(&mut scenario, MALICIOUS_USER);
        
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
        
        let received_coin = escrow::fill_escrow(
            &mut escrow,
            &mut registry,
            secret,
            &clock,
            ctx(&mut scenario)
        );
        
        coin::burn_for_testing(received_coin);
        test::return_shared(escrow);
        test::return_shared(registry);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_SECRET)]
    fun test_fill_escrow_invalid_secret() {
        let mut scenario = test::begin(MAKER);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        escrow::share_escrow(escrow);
        
        next_tx(&mut scenario, TAKER);
        
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
        
        // Try to fill with wrong secret
        let wrong_secret = b"wrong_secret";
        let received_coin = escrow::fill_escrow(
            &mut escrow,
            &mut registry,
            wrong_secret,
            &clock,
            ctx(&mut scenario)
        );
        
        coin::burn_for_testing(received_coin);
        test::return_shared(escrow);
        test::return_shared(registry);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_EXPIRED)]
    fun test_fill_escrow_expired() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        escrow::share_escrow(escrow);
        
        // Advance time past expiry
        clock::increment_for_testing(&mut clock, ONE_HOUR_MS + 1000);
        
        next_tx(&mut scenario, TAKER);
        
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
        
        // Try to fill expired escrow
        let received_coin = escrow::fill_escrow(
            &mut escrow,
            &mut registry,
            secret,
            &clock,
            ctx(&mut scenario)
        );
        
        coin::burn_for_testing(received_coin);
        test::return_shared(escrow);
        test::return_shared(registry);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_used_secrets_registry() {
        let mut scenario = test::begin(MAKER);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin1 = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash1 = string::utf8(b"0x1234567890abcdef");
        
        // Create one escrow
        let escrow1 = escrow::create_escrow<SUI>(
            coin1,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash1,
            &clock,
            ctx(&mut scenario)
        );
        
        escrow::share_escrow(escrow1);
        
        next_tx(&mut scenario, TAKER);
        
        let mut escrow1 = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
        
        // Initially no secrets used
        assert_eq(escrow::get_used_secrets_count(&registry), 0);
        assert_eq(escrow::is_secret_used(&registry, &secret), false);
        
        // Fill first escrow successfully
        let received_coin1 = escrow::fill_escrow(
            &mut escrow1,
            &mut registry,
            secret,
            &clock,
            ctx(&mut scenario)
        );
        
        // Verify secret is now in the registry
        assert_eq(escrow::get_used_secrets_count(&registry), 1);
        assert_eq(escrow::is_secret_used(&registry, &secret), true);
        
        coin::burn_for_testing(received_coin1);
        test::return_shared(escrow1);
        test::return_shared(registry);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_MAKER)]
    fun test_cancel_escrow_wrong_maker() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        escrow::share_escrow(escrow);
        
        // Advance time past expiry
        clock::increment_for_testing(&mut clock, ONE_HOUR_MS + 1000);
        
        // Malicious user tries to cancel
        next_tx(&mut scenario, MALICIOUS_USER);
        
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        
        let refunded_coin = escrow::cancel_escrow(
            &mut escrow,
            &clock,
            ctx(&mut scenario)
        );
        
        coin::burn_for_testing(refunded_coin);
        test::return_shared(escrow);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_NOT_EXPIRED)]
    fun test_cancel_escrow_not_expired() {
        let mut scenario = test::begin(MAKER);
        let clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        escrow::share_escrow(escrow);
        
        // Try to cancel before expiry
        next_tx(&mut scenario, MAKER);
        
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        
        let refunded_coin = escrow::cancel_escrow(
            &mut escrow,
            &clock,
            ctx(&mut scenario)
        );
        
        coin::burn_for_testing(refunded_coin);
        test::return_shared(escrow);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_ALREADY_FILLED)]
    fun test_cancel_filled_escrow() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        escrow::share_escrow(escrow);
        
        // Fill the escrow first
        next_tx(&mut scenario, TAKER);
        
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
        
        let received_coin = escrow::fill_escrow(
            &mut escrow,
            &mut registry,
            secret,
            &clock,
            ctx(&mut scenario)
        );
        
        coin::burn_for_testing(received_coin);
        test::return_shared(registry);
        
        // Now try to cancel the filled escrow
        clock::increment_for_testing(&mut clock, ONE_HOUR_MS + 1000);
        
        next_tx(&mut scenario, MAKER);
        
        let refunded_coin = escrow::cancel_escrow(
            &mut escrow,
            &clock,
            ctx(&mut scenario)
        );
        
        coin::burn_for_testing(refunded_coin);
        test::return_shared(escrow);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_can_fill_functionality() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        // Test can_fill when active
        assert_eq(escrow::can_fill(&escrow, &clock), true);
        
        escrow::share_escrow(escrow);
        
        // Test after time expiry
        clock::increment_for_testing(&mut clock, ONE_HOUR_MS + 1000);
        
        next_tx(&mut scenario, TAKER);
        
        let escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        
        // Test can_fill when expired
        assert_eq(escrow::can_fill(&escrow, &clock), false);
        
        test::return_shared(escrow);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_is_expired_functionality() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let escrow = escrow::create_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        // Test is_expired when active
        assert_eq(escrow::is_expired(&escrow, &clock), false);
        
        escrow::share_escrow(escrow);
        
        // Test after time expiry
        clock::increment_for_testing(&mut clock, ONE_HOUR_MS + 1000);
        
        next_tx(&mut scenario, TAKER);
        
        let escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        
        // Test is_expired when expired
        assert_eq(escrow::is_expired(&escrow, &clock), true);
        
        test::return_shared(escrow);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
}