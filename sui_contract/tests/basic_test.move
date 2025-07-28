#[test_only]
module fusion_plus_crosschain::basic_test {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self};
    use sui::clock::{Self};
    use sui::sui::SUI;
    use sui::test_utils::assert_eq;
    use std::string;
    use sui::hash;
    use fusion_plus_crosschain::cross_chain_escrow::{
        Self as escrow, CrossChainEscrow, UsedSecretsRegistry
    };

    // Test constants
    const MAKER: address = @0xA;
    const TAKER: address = @0xB;
    const AMOUNT: u64 = 1000;
    const ONE_HOUR_MS: u64 = 3600000;

    #[test]
    fun test_create_and_fill_escrow() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        // Create test data
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        // Create and share escrow - this prevents UnusedValueWithoutDrop
        let escrow_id = escrow::create_and_share_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        // Verify escrow_id is valid
        assert!(sui::object::id_to_address(&escrow_id) != @0x0, 0);
        
        next_tx(&mut scenario, TAKER);
        
        // Get shared objects
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
        
        // Verify escrow properties after sharing
        let (maker, taker, total_amount, remaining_amount, stored_hash_lock, stored_time_lock, is_filled, created_at, stored_ethereum_order_hash) = 
            escrow::get_escrow_info(&escrow);
        
        assert_eq(maker, MAKER);
        assert_eq(taker, TAKER);
        assert_eq(total_amount, AMOUNT);
        assert_eq(remaining_amount, AMOUNT);
        assert_eq(stored_hash_lock, hash_lock);
        assert_eq(stored_time_lock, time_lock);
        assert_eq(is_filled, false);
        assert_eq(created_at, clock::timestamp_ms(&clock));
        assert_eq(stored_ethereum_order_hash, ethereum_order_hash);
        
        // Fill the escrow
        let received_coin = escrow::fill_escrow(
            &mut escrow,
            &mut registry,
            secret,
            &clock,
            ctx(&mut scenario)
        );
        
        // Verify taker received the coin
        assert_eq(coin::value(&received_coin), AMOUNT);
        
        // Verify escrow is filled
        let (_, _, _, remaining_amount, _, _, is_filled, _, _) = escrow::get_escrow_info(&escrow);
        assert_eq(is_filled, true);
        assert_eq(remaining_amount, 0);
        
        // Verify secret was stored
        let stored_secret = escrow::get_secret(&escrow);
        assert_eq(stored_secret, secret);
        
        // Verify secret was added to registry
        assert_eq(escrow::get_used_secrets_count(&registry), 1);
        assert_eq(escrow::is_secret_used(&registry, &secret), true);
        
        coin::burn_for_testing(received_coin);
        test::return_shared(escrow);
        test::return_shared(registry);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_verify_secret() {
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let wrong_secret = b"wrong_secret";
        
        assert_eq(escrow::verify_secret(secret, hash_lock), true);
        assert_eq(escrow::verify_secret(wrong_secret, hash_lock), false);
    }

    #[test]
    fun test_create_hash_lock() {
        let secret = b"test_secret";
        let expected_hash = hash::keccak256(&secret);
        
        assert_eq(escrow::create_hash_lock(secret), expected_hash);
    }

    #[test]
    fun test_batch_hash_locks() {
        let secrets = vector[b"secret1", b"secret2", b"secret3"];
        let hash_locks = escrow::create_batch_hash_locks(secrets);
        
        assert_eq(vector::length(&hash_locks), 3);
        assert_eq(*vector::borrow(&hash_locks, 0), hash::keccak256(&b"secret1"));
        assert_eq(*vector::borrow(&hash_locks, 1), hash::keccak256(&b"secret2"));
        assert_eq(*vector::borrow(&hash_locks, 2), hash::keccak256(&b"secret3"));
    }

    #[test]
    fun test_cancel_escrow() {
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
        
        let escrow_id = escrow::create_and_share_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        // Verify escrow_id is valid
        assert!(sui::object::id_to_address(&escrow_id) != @0x0, 0);
        
        // Advance time past expiry
        clock::increment_for_testing(&mut clock, ONE_HOUR_MS + 1000);
        
        next_tx(&mut scenario, MAKER);
        
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        
        // Cancel the escrow
        let refunded_coin = escrow::cancel_escrow(
            &mut escrow,
            &clock,
            ctx(&mut scenario)
        );
        
        // Verify maker received the refund
        assert_eq(coin::value(&refunded_coin), AMOUNT);
        
        coin::burn_for_testing(refunded_coin);
        test::return_shared(escrow);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
}