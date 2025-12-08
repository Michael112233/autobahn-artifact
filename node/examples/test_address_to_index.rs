// Test program for address_to_index function
use config::{Committee, Import, BASE_PORT};
use std::net::SocketAddr;

fn main() {
    // Load the committee from the generated file
    let committee = match Committee::import("benchmark/.committee.json") {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Failed to load committee: {:?}", e);
            eprintln!("Make sure to run 'fab local' first to generate .committee.json");
            return;
        }
    };

    println!("Committee size: {} authorities", committee.size());
    
    // Calculate worker_num
    let primary_num = committee.size();
    let total_workers: usize = committee.authorities.values().map(|x| x.workers.len()).sum();
    let worker_num = total_workers / primary_num;
    println!("Workers per authority: {}", worker_num);
    println!("Ports per authority calculation:");
    println!("  Formula: (port - BASE_PORT) / (worker_num * 3 + 2)");
    println!("  Divisor: worker_num * 3 + 2 = {} * 3 + 2 = {}", worker_num, worker_num * 3 + 2);
    println!("  Actual ports per authority: 1 (consensus) + 2 (primary) + {} * 3 (workers) = {}", 
             worker_num, 3 + 3 * worker_num);
    println!("  GROUP array size: {}", adversary::attack::GROUP.len());
    println!();

    // Test all addresses from the committee
    println!("Testing address_to_index for all addresses:");
    println!("{:-<80}", "");
    
    for (idx, (name, authority)) in committee.authorities.iter().enumerate() {
        println!("\nAuthority {} (expected index {}):", idx, idx);
        println!("  Name: {:?}", name);
        
        // Test consensus address
        let consensus_addr = authority.consensus.consensus_to_consensus;
        let consensus_idx = committee.address_to_index(&consensus_addr);
        println!("    consensus_to_consensus: {} -> index {}", consensus_addr, consensus_idx);
        
        // Test primary addresses
        let primary_primary = authority.primary.primary_to_primary;
        let primary_primary_idx = committee.address_to_index(&primary_primary);
        println!("    primary_to_primary: {} -> index {}", primary_primary, primary_primary_idx);
        
        let worker_primary = authority.primary.worker_to_primary;
        let worker_primary_idx = committee.address_to_index(&worker_primary);
        println!("    worker_to_primary: {} -> index {}", worker_primary, worker_primary_idx);
        
        // Test worker addresses
        for (worker_id, worker_addr) in &authority.workers {
            let primary_worker = worker_addr.primary_to_worker;
            let primary_worker_idx = committee.address_to_index(&primary_worker);
            println!("    Worker {} primary_to_worker: {} -> index {}", worker_id, primary_worker, primary_worker_idx);
            
            let transactions = worker_addr.transactions;
            let transactions_idx = committee.address_to_index(&transactions);
            println!("    Worker {} transactions: {} -> index {}", worker_id, transactions, transactions_idx);
            
            let worker_worker = worker_addr.worker_to_worker;
            let worker_worker_idx = committee.address_to_index(&worker_worker);
            println!("    Worker {} worker_to_worker: {} -> index {}", worker_id, worker_worker, worker_worker_idx);
        }
        
        // Verify expected index
        let expected_idx = idx;
        println!("  Expected index: {}", expected_idx);
        
        // Check if all addresses map to the same index
        let all_indices = vec![
            consensus_idx,
            primary_primary_idx,
            worker_primary_idx,
        ];
        let worker_indices: Vec<usize> = authority.workers.values().flat_map(|w| {
            vec![
                committee.address_to_index(&w.primary_to_worker),
                committee.address_to_index(&w.transactions),
                committee.address_to_index(&w.worker_to_worker),
            ]
        }).collect();
        
        let all_same = all_indices.iter().all(|&i| i == expected_idx) 
            && worker_indices.iter().all(|&i| i == expected_idx);
        
        if all_same {
            println!("  ✓ All addresses correctly map to index {}", expected_idx);
        } else {
            println!("  ✗ ERROR: Not all addresses map to expected index!");
            println!("    Primary addresses indices: {:?}", all_indices);
            println!("    Worker addresses indices: {:?}", worker_indices);
        }
    }
    
    println!("\n{:-<80}", "");
    println!("\nTesting edge cases:");
    
    // Test with invalid addresses
    let test_addresses = vec![
        SocketAddr::from(([127, 0, 0, 1], 2999)), // Before BASE_PORT
        SocketAddr::from(([127, 0, 0, 1], 3000)), // BASE_PORT
        SocketAddr::from(([127, 0, 0, 1], 4000)), // Way beyond
    ];
    
    for addr in test_addresses {
        let idx = committee.address_to_index(&addr);
        println!("  {} -> index {} (port: {})", addr, idx, addr.port());
    }
    
    // Check GROUP array bounds and find addresses returning index 7
    println!("\n{:-<80}", "");
    println!("\nChecking GROUP array bounds and finding addresses that return index 7:");
    println!("  GROUP array size: {} (valid indices: 0-{})", 
             adversary::attack::GROUP.len(), 
             adversary::attack::GROUP.len() - 1);
    println!("  Committee size: {}", committee.size());
    
    // Test all addresses and check if any index exceeds GROUP bounds
    let mut max_index = 0;
    let mut out_of_bounds = Vec::new();
    let mut index_7_addresses = Vec::new();
    let mut all_addresses_with_indices = Vec::new();
    
    for (auth_idx, (name, authority)) in committee.authorities.iter().enumerate() {
        let addresses = vec![
            ("consensus_to_consensus", authority.consensus.consensus_to_consensus),
            ("primary_to_primary", authority.primary.primary_to_primary),
            ("worker_to_primary", authority.primary.worker_to_primary),
        ];
        
        for (addr_type, addr) in addresses {
            let idx = committee.address_to_index(&addr);
            let port = addr.port();
            let calculation = format!("({} - {}) / {} = {} / {} = {}", 
                                     port, 
                                     BASE_PORT,
                                     worker_num * 3 + 2,
                                     port as i32 - BASE_PORT as i32,
                                     worker_num * 3 + 2,
                                     idx);
            
            all_addresses_with_indices.push((auth_idx, addr_type.to_string(), addr, idx, calculation.clone()));
            max_index = max_index.max(idx);
            
            if idx == 7 {
                index_7_addresses.push((auth_idx, addr_type.to_string(), addr, idx, calculation.clone()));
            }
            
            if idx >= adversary::attack::GROUP.len() {
                out_of_bounds.push((auth_idx, addr_type.to_string(), addr, idx, calculation.clone()));
            }
        }
        
        for (worker_id, worker_addr) in &authority.workers {
            let addresses = vec![
                ("primary_to_worker", worker_addr.primary_to_worker),
                ("transactions", worker_addr.transactions),
                ("worker_to_worker", worker_addr.worker_to_worker),
            ];
            
            for (addr_type, addr) in addresses {
                let idx = committee.address_to_index(&addr);
                let port = addr.port();
                let calculation = format!("({} - {}) / {} = {} / {} = {}", 
                                         port, 
                                         BASE_PORT,
                                         worker_num * 3 + 2,
                                         port as i32 - BASE_PORT as i32,
                                         worker_num * 3 + 2,
                                         idx);
                
                all_addresses_with_indices.push((auth_idx, 
                                                format!("worker_{}_{}", worker_id, addr_type), 
                                                addr, idx, calculation.clone()));
                max_index = max_index.max(idx);
                
                if idx == 7 {
                    index_7_addresses.push((auth_idx, 
                                          format!("worker_{}_{}", worker_id, addr_type), 
                                          addr, idx, calculation.clone()));
                }
                
                if idx >= adversary::attack::GROUP.len() {
                    out_of_bounds.push((auth_idx, 
                                       format!("worker_{}_{}", worker_id, addr_type), 
                                       addr, idx, calculation.clone()));
                }
            }
        }
    }
    
    println!("\n  Maximum index found: {}", max_index);
    println!("  GROUP array bounds: 0..{}", adversary::attack::GROUP.len());
    
    // Show addresses that return index 7
    if !index_7_addresses.is_empty() {
        println!("\n  ⚠️  Found {} address(es) that return index 7:", index_7_addresses.len());
        for (auth_idx, addr_type, addr, idx, calc) in &index_7_addresses {
            println!("    Authority {}, {}: {} -> index {}", auth_idx, addr_type, addr, idx);
            println!("      Calculation: {}", calc);
        }
    } else {
        println!("\n  ✓ No addresses return index 7");
    }
    
    // Show all out-of-bounds addresses
    if out_of_bounds.is_empty() {
        println!("\n  ✓ All addresses are within GROUP array bounds");
    } else {
        println!("\n  ✗ ERROR: Found {} addresses that exceed GROUP array bounds:", out_of_bounds.len());
        for (auth_idx, addr_type, addr, idx, calc) in &out_of_bounds {
            println!("    Authority {}, {}: {} -> index {} (exceeds bounds)", auth_idx, addr_type, addr, idx);
            println!("      Calculation: {}", calc);
        }
    }
    
    // Show all addresses sorted by index for debugging
    println!("\n{:-<80}", "");
    println!("\nAll addresses sorted by calculated index:");
    all_addresses_with_indices.sort_by_key(|(_, _, _, idx, _)| *idx);
    for (auth_idx, addr_type, addr, idx, calc) in &all_addresses_with_indices {
        let marker = if *idx >= adversary::attack::GROUP.len() { " ⚠️ OUT OF BOUNDS" } 
                     else if *idx == 7 { " ⚠️ INDEX 7" } 
                     else { "" };
        println!("  Index {}: Authority {}, {}: {} {}", idx, auth_idx, addr_type, addr, marker);
    }
}

