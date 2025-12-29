pub mod attack;

// Re-export commonly used items for convenience
pub use attack::{start_attack_scheduler, NETWORK_PARTITION, TRIGGER_NETWORK_INTERRUPT};
