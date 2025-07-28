/// @title example_test
/// @dev Test example functions to ensure UnusedValueWithoutDrop error is fixed
#[test_only]
module fusion_plus_crosschain::example_test {
    use sui::test_scenario::{Self, ctx};
    use sui::coin;
    use sui::sui::SUI;
    use sui::clock;
    use std::vector;
    use fusion_plus_crosschain::escrow_example;
    use fusion_plus_crosschain::cross_chain_escrow::{Self, CrossChainEscrow, UsedSecretsRegistry};

    const USER1: address = @0xA;
    const USER2: address = @0xB;

    #[test]
    fun test_create_simple_escrow_no_error() {
        let mut scenario = test_scenario::begin(USER1);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let coin = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));
            let secret = b"test_secret";
            
            // This should not cause UnusedValueWithoutDrop error
            escrow_example::create_simple_escrow(
                coin,
                USER2,
                secret,
                &clock,
                ctx(&mut scenario)
            );
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_create_batch_escrows_no_error() {
        let mut scenario = test_scenario::begin(USER1);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let coin1 = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));
            let coin2 = coin::mint_for_testing<SUI>(2000, ctx(&mut scenario));
            let coins = vector[coin1, coin2];
            
            let secret1 = b"secret1";
            let secret2 = b"secret2";
            let secrets = vector[secret1, secret2];
            
            // This should not cause UnusedValueWithoutDrop error
            escrow_example::create_batch_escrows(
                coins,
                USER2,
                secrets,
                &clock,
                ctx(&mut scenario)
            );
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_fill_escrow_example_no_error() {
        let mut scenario = test_scenario::begin(USER1);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Create registry first
        test_scenario::next_tx(&mut scenario, USER1);
        {
            cross_chain_escrow::init_for_testing(ctx(&mut scenario));
        };

        // Create escrow
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let coin = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));
            let secret = b"test_secret";
            
            escrow_example::create_simple_escrow(
                coin,
                USER2,
                secret,
                &clock,
                ctx(&mut scenario)
            );
        };

        // Fill escrow
        test_scenario::next_tx(&mut scenario, USER2);
        {
            let mut registry = test_scenario::take_shared<UsedSecretsRegistry>(&scenario);
            let mut escrow = test_scenario::take_shared<CrossChainEscrow<SUI>>(&scenario);
            let secret = b"test_secret";
            
            // This should not cause UnusedValueWithoutDrop error
            escrow_example::fill_escrow_example(
                &mut escrow,
                &mut registry,
                secret,
                &clock,
                ctx(&mut scenario)
            );
            
            test_scenario::return_shared(registry);
            test_scenario::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_expired_escrow_no_error() {
        let mut scenario = test_scenario::begin(USER1);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Create escrow
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let coin = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));
            let secret = b"test_secret";
            
            escrow_example::create_simple_escrow(
                coin,
                USER2,
                secret,
                &clock,
                ctx(&mut scenario)
            );
        };

        // Wait for expiration
        clock::increment_for_testing(&mut clock, 7 * 24 * 60 * 60 * 1000 + 1); // 7 days + 1ms

        // Cancel escrow
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let mut escrow = test_scenario::take_shared<CrossChainEscrow<SUI>>(&scenario);
            
            // This should not cause UnusedValueWithoutDrop error
            escrow_example::cancel_expired_escrow(
                &mut escrow,
                &clock,
                ctx(&mut scenario)
            );
            
            test_scenario::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_check_escrow_status_no_error() {
        let mut scenario = test_scenario::begin(USER1);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Create escrow
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let coin = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));
            let secret = b"test_secret";
            
            escrow_example::create_simple_escrow(
                coin,
                USER2,
                secret,
                &clock,
                ctx(&mut scenario)
            );
        };

        // Check status
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let escrow = test_scenario::take_shared<CrossChainEscrow<SUI>>(&scenario);
            
            // This should not cause UnusedValueWithoutDrop error
            let (is_expired, can_fill, is_filled) = escrow_example::check_escrow_status(
                &escrow,
                &clock
            );
            
            // Verify results
            assert!(!is_expired, 1);
            assert!(can_fill, 2);
            assert!(!is_filled, 3);
            
            test_scenario::return_shared(escrow);
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_multiple_escrow_operations_no_error() {
        let mut scenario = test_scenario::begin(USER1);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // Create registry first
        test_scenario::next_tx(&mut scenario, USER1);
        {
            cross_chain_escrow::init_for_testing(ctx(&mut scenario));
        };

        // Create multiple escrows
        test_scenario::next_tx(&mut scenario, USER1);
        {
            let coin1 = coin::mint_for_testing<SUI>(1000, ctx(&mut scenario));
            let coin2 = coin::mint_for_testing<SUI>(2000, ctx(&mut scenario));
            let coin3 = coin::mint_for_testing<SUI>(3000, ctx(&mut scenario));
            
            let secret1 = b"secret1";
            let secret2 = b"secret2";
            let secret3 = b"secret3";
            
            // Create individual escrows - should not cause UnusedValueWithoutDrop error
            escrow_example::create_simple_escrow(coin1, USER2, secret1, &clock, ctx(&mut scenario));
            escrow_example::create_simple_escrow(coin2, USER2, secret2, &clock, ctx(&mut scenario));
            escrow_example::create_simple_escrow(coin3, USER2, secret3, &clock, ctx(&mut scenario));
        };

        // Verify all escrows were created without errors
        test_scenario::next_tx(&mut scenario, USER1);
        {
            // Just verify the transaction completed successfully
            // The fact that we reached this point means no UnusedValueWithoutDrop error occurred
        };
        
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}