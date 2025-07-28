#[test_only]
module fusion_plus_crosschain::create_and_share_test {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::coin::{Self};
    use sui::clock::{Self};
    use sui::sui::SUI;
    use sui::test_utils::assert_eq;
    use sui::object::{Self};
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
    fun test_create_and_share_escrow_success() {
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
        
        // Create and share escrow - this should not cause UnusedValueWithoutDrop
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
        assert!(object::id_to_address(&escrow_id) != @0x0, 0);
        
        next_tx(&mut scenario, TAKER);
        
        // Get shared objects
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
        
        // Verify escrow properties
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
        let (_, _, _, _, _, _, is_filled, _, _) = escrow::get_escrow_info(&escrow);
        assert_eq(is_filled, true);
        
        // Verify secret was stored
        let stored_secret = escrow::get_secret(&escrow);
        assert_eq(stored_secret, secret);
        
        coin::burn_for_testing(received_coin);
        test::return_shared(escrow);
        test::return_shared(registry);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_create_and_share_escrow_multiple() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        // Create multiple escrows without causing UnusedValueWithoutDrop
        let secret1 = b"secret1";
        let secret2 = b"secret2";
        let secret3 = b"secret3";
        
        let hash_lock1 = hash::keccak256(&secret1);
        let hash_lock2 = hash::keccak256(&secret2);
        let hash_lock3 = hash::keccak256(&secret3);
        
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        let coin1 = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let coin2 = coin::mint_for_testing<SUI>(AMOUNT * 2, ctx(&mut scenario));
        let coin3 = coin::mint_for_testing<SUI>(AMOUNT * 3, ctx(&mut scenario));
        
        // Create multiple escrows
        let escrow_id1 = escrow::create_and_share_escrow<SUI>(
            coin1, TAKER, hash_lock1, time_lock, ethereum_order_hash, &clock, ctx(&mut scenario)
        );
        
        let escrow_id2 = escrow::create_and_share_escrow<SUI>(
            coin2, TAKER, hash_lock2, time_lock, ethereum_order_hash, &clock, ctx(&mut scenario)
        );
        
        let escrow_id3 = escrow::create_and_share_escrow<SUI>(
            coin3, TAKER, hash_lock3, time_lock, ethereum_order_hash, &clock, ctx(&mut scenario)
        );
        
        // Verify all escrow IDs are valid and different
        assert!(object::id_to_address(&escrow_id1) != @0x0, 0);
        assert!(object::id_to_address(&escrow_id2) != @0x0, 0);
        assert!(object::id_to_address(&escrow_id3) != @0x0, 0);
        
        assert!(escrow_id1 != escrow_id2, 0);
        assert!(escrow_id2 != escrow_id3, 0);
        assert!(escrow_id1 != escrow_id3, 0);
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_create_and_share_escrow_with_expiry() {
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
        
        // Create and share escrow
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
        assert!(object::id_to_address(&escrow_id) != @0x0, 0);
        
        // Advance time past expiry
        clock::increment_for_testing(&mut clock, ONE_HOUR_MS + 1000);
        
        next_tx(&mut scenario, MAKER);
        
        // Get shared escrow
        let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        
        // Verify escrow is expired
        assert!(escrow::is_expired(&escrow, &clock), 0);
        assert!(!escrow::can_fill(&escrow, &clock), 0);
        
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

    #[test]
    fun test_create_and_share_escrow_status_checks() {
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
        
        // Create and share escrow
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
        assert!(object::id_to_address(&escrow_id) != @0x0, 0);
        
        next_tx(&mut scenario, TAKER);
        
        // Get shared escrow
        let escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
        
        // Test status checks
        assert!(!escrow::is_expired(&escrow, &clock), 0);
        assert!(escrow::can_fill(&escrow, &clock), 0);
        
        // Verify secret verification works
        assert!(escrow::verify_secret(secret, hash_lock), 0);
        assert!(!escrow::verify_secret(b"wrong_secret", hash_lock), 0);
        
        test::return_shared(escrow);
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test, expected_failure(abort_code = escrow::E_INVALID_AMOUNT)]
    fun test_create_and_share_escrow_with_zero_amount_fails() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        // Create test data with zero amount
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        let time_lock = clock::timestamp_ms(&clock) + ONE_HOUR_MS;
        let coin = coin::mint_for_testing<SUI>(0, ctx(&mut scenario)); // Zero amount
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        // This should fail due to zero amount
        escrow::create_and_share_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test, expected_failure(abort_code = escrow::E_INVALID_TIME_LOCK)]
    fun test_create_and_share_escrow_with_past_time_lock_fails() {
        let mut scenario = test::begin(MAKER);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Initialize the module
        escrow::init_for_testing(ctx(&mut scenario));
        
        next_tx(&mut scenario, MAKER);
        
        // Create test data with past time lock
        let secret = b"test_secret";
        let hash_lock = hash::keccak256(&secret);
        clock::increment_for_testing(&mut clock, 2000); // Move time forward first
        let time_lock = clock::timestamp_ms(&clock) - 1000; // Past time
        let coin = coin::mint_for_testing<SUI>(AMOUNT, ctx(&mut scenario));
        let ethereum_order_hash = string::utf8(b"0x1234567890abcdef");
        
        // This should fail due to invalid time lock
        escrow::create_and_share_escrow<SUI>(
            coin,
            TAKER,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            &clock,
            ctx(&mut scenario)
        );
        
        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
}