/// @title escrow_example
/// @dev Example usage of the cross-chain escrow system
module fusion_plus_crosschain::escrow_example {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Clock};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use std::string;
    use std::vector;
    use fusion_plus_crosschain::cross_chain_escrow::{Self, CrossChainEscrow, UsedSecretsRegistry};
    use fusion_plus_crosschain::hash_lock;
    use fusion_plus_crosschain::time_lock;

    /// Example: Create a simple escrow
    public entry fun create_simple_escrow(
        coin: Coin<SUI>,
        taker: address,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let hash_lock = hash_lock::create_hash_lock(secret);
        let time_lock = time_lock::create_time_lock(
            time_lock::standard_duration(),
            clock
        );
        let ethereum_order_hash = string::utf8(b"example_order_hash");
        
        cross_chain_escrow::create_and_share_escrow<SUI>(
            coin,
            taker,
            hash_lock,
            time_lock,
            ethereum_order_hash,
            clock,
            ctx
        );
    }
    
    /// Example: Fill an escrow with the correct secret
    public entry fun fill_escrow_example(
        escrow: &mut CrossChainEscrow<SUI>,
        registry: &mut UsedSecretsRegistry,
        secret: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let coin = cross_chain_escrow::fill_escrow(
            escrow,
            registry,
            secret,
            clock,
            ctx
        );
        
        // Transfer the coin to the caller
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(coin, sender);
    }
    
    /// Example: Cancel an expired escrow
    public entry fun cancel_expired_escrow(
        escrow: &mut CrossChainEscrow<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let coin = cross_chain_escrow::cancel_escrow(
            escrow,
            clock,
            ctx
        );
        
        // Transfer the coin back to the caller (original maker)
        let sender = tx_context::sender(ctx);
        transfer::public_transfer(coin, sender);
    }
    
    /// Example: Create multiple escrows in batch
    public entry fun create_batch_escrows(
        mut coins: vector<Coin<SUI>>,
        taker: address,
        secrets: vector<vector<u8>>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let hash_locks = hash_lock::create_batch_hash_locks(secrets);
        let time_lock = time_lock::create_time_lock(
            time_lock::standard_duration(),
            clock
        );
        
        let mut i = 0;
        let len = vector::length(&coins);
        while (i < len) {
            let coin = vector::pop_back(&mut coins);
            let hash_lock = *vector::borrow(&hash_locks, i);
            let ethereum_order_hash = string::utf8(b"batch_order_");
            
            cross_chain_escrow::create_and_share_escrow<SUI>(
                coin,
                taker,
                hash_lock,
                time_lock,
                ethereum_order_hash,
                clock,
                ctx
            );
            
            i = i + 1;
        };
        
        // Destroy the empty vector
        vector::destroy_empty(coins);
    }
    
    /// Example: Check escrow status
    public fun check_escrow_status<T>(
        escrow: &CrossChainEscrow<T>,
        clock: &Clock
    ): (bool, bool, bool) {
        let is_expired = cross_chain_escrow::is_expired(escrow, clock);
        let can_fill = cross_chain_escrow::can_fill(escrow, clock);
        let (_, _, _, _, _, _, is_filled, _, _) = cross_chain_escrow::get_escrow_info(escrow);
        
        (is_expired, can_fill, is_filled)
    }
}