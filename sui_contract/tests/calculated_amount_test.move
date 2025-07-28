#[test_only]
module fusion_plus_crosschain::calculated_amount_test {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::clock::{Self, Clock};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use std::string;
    use fusion_plus_crosschain::cross_chain_escrow::{
        Self, CrossChainEscrow, UsedSecretsRegistry
    };
    use fusion_plus_crosschain::hash_lock;

    const ALICE: address = @0xa11ce;
    const BOB: address = @0xb0b;

    #[test]
    fun test_calculated_amount_fill_escrow() {
        let mut scenario = test::begin(ALICE);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        // 現在時刻を設定
        clock::set_for_testing(&mut clock, 1000);
        
        // レジストリの初期化
        next_tx(&mut scenario, ALICE);
        {
            cross_chain_escrow::init_for_testing(ctx(&mut scenario));
        };

        // シミュレーション：
        // 入力: 0.00001 ETH
        // レート: 887.30 SUI/ETH
        // 手数料: 0.3%
        // 計算後見積額: 0.00001 * 887.30 * 0.997 = 0.008846991 SUI
        // MIST換算: 8846991 MIST (1 SUI = 1e9 MIST)
        
        let input_amount_eth = 10000; // 0.00001 ETH in wei (10^18 = 1 ETH)
        let calculated_sui_amount = 8846991; // 0.008846991 SUI in MIST
        
        // ALICEがエスクロー作成（計算後の金額でcoinを作成）
        next_tx(&mut scenario, ALICE);
        {
            let ctx = ctx(&mut scenario);
            
            // 計算後の金額でSUIコインを作成
            let coin = coin::mint_for_testing<SUI>(calculated_sui_amount, ctx);
            
            // シークレットとハッシュロック作成
            let secret = b"test_secret_123";
            let hash_lock = hash_lock::create_hash_lock(secret);
            
            // 1時間後の期限
            let time_lock = 1000 + 3600000;
            
            let escrow_id = cross_chain_escrow::create_and_share_escrow<SUI>(
                coin,
                BOB,
                hash_lock,
                time_lock,
                string::utf8(b"eth_order_hash_123"),
                &clock,
                ctx
            );
            
            // エスクロー情報の確認
            next_tx(&mut scenario, BOB);
            {
                let escrow = test::take_shared_by_id<CrossChainEscrow<SUI>>(&scenario, escrow_id);
                let (maker, taker, total_amount, remaining_amount, hash_lock_stored, time_lock_stored, is_filled, created_at, eth_hash) = 
                    cross_chain_escrow::get_escrow_info(&escrow);
                
                // エスクローに格納された金額が計算後の金額と一致することを確認
                assert!(total_amount == calculated_sui_amount, 0);
                assert!(remaining_amount == calculated_sui_amount, 0);
                assert!(maker == ALICE, 1);
                assert!(taker == BOB, 2);
                assert!(!is_filled, 3);
                
                test::return_shared(escrow);
            };
        };

        // BOBがエスクローをfill（シークレットを明かして受け取り）
        next_tx(&mut scenario, BOB);
        {
            let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
            let mut escrow = test::take_shared<CrossChainEscrow<SUI>>(&scenario);
            let secret = b"test_secret_123";
            
            // エスクローをfillして計算後の金額を受け取る
            let received_coin = cross_chain_escrow::fill_escrow<SUI>(
                &mut escrow,
                &mut registry,
                secret,
                &clock,
                ctx(&mut scenario)
            );
            
            // 受け取った金額が計算後の見積額と一致することを確認
            let received_amount = coin::value(&received_coin);
            assert!(received_amount == calculated_sui_amount, 4);
            
            // エスクローがfill済みになっていることを確認
            let (_, _, _, _, _, _, is_filled, _, _) = cross_chain_escrow::get_escrow_info(&escrow);
            assert!(is_filled, 5);
            
            coin::burn_for_testing(received_coin);
            test::return_shared(registry);
            test::return_shared(escrow);
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }

    #[test]
    fun test_different_input_calculated_amounts() {
        let mut scenario = test::begin(ALICE);
        let mut clock = clock::create_for_testing(ctx(&mut scenario));
        
        clock::set_for_testing(&mut clock, 1000);
        
        next_tx(&mut scenario, ALICE);
        {
            cross_chain_escrow::init_for_testing(ctx(&mut scenario));
        };

        // ケース1: より大きな入力額
        // 入力: 0.0001 ETH
        // レート: 887.30 SUI/ETH  
        // 計算後見積額: 0.0001 * 887.30 * 0.997 = 0.08846991 SUI
        let calculated_sui_amount_1 = 88469910; // 0.08846991 SUI in MIST
        
        next_tx(&mut scenario, ALICE);
        {
            let ctx = ctx(&mut scenario);
            let coin = coin::mint_for_testing<SUI>(calculated_sui_amount_1, ctx);
            let secret = b"secret_case_1";
            let hash_lock = hash_lock::create_hash_lock(secret);
            let time_lock = 1000 + 3600000;
            
            let escrow_id = cross_chain_escrow::create_and_share_escrow<SUI>(
                coin,
                BOB,
                hash_lock,
                time_lock,
                string::utf8(b"eth_order_hash_case1"),
                &clock,
                ctx
            );
            
            next_tx(&mut scenario, BOB);
            {
                let mut registry = test::take_shared<UsedSecretsRegistry>(&scenario);
                let mut escrow = test::take_shared_by_id<CrossChainEscrow<SUI>>(&scenario, escrow_id);
                
                let received_coin = cross_chain_escrow::fill_escrow<SUI>(
                    &mut escrow,
                    &mut registry,
                    secret,
                    &clock,
                    ctx(&mut scenario)
                );
                
                // より大きな計算後金額を正確に受け取れることを確認
                assert!(coin::value(&received_coin) == calculated_sui_amount_1, 6);
                
                coin::burn_for_testing(received_coin);
                test::return_shared(registry);
                test::return_shared(escrow);
            };
        };

        clock::destroy_for_testing(clock);
        test::end(scenario);
    }
}