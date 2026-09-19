# Parameters
const W = 50.0
const D1 = 1000.0
const D2 = 1000.0
const D3 = 250.0
const r0 = 1500.0
const rc = 3000.0
const α = 0.25
const β = 0

const date_0 = Date("2004-01-01")
const date_1 = Date("2010-01-01")

function update_rating(r1::Float64, r2::Float64, wm::Float32, we::Float32, date::Date)
    a1 = wm > 0.0 ? 1.0 : (wm < 0.0 ? 0.0 : 0.5)
    wm = abs(wm)
    if date < date_0
        wm *= 2
    end
    if date < date_1
        wm *= 2
    end
    
    # Calculate opponent's result
    a2 = 1.0 - a1
    
    # Step 1: Calculate ELO expectation
    e1 = 1.0 / (1.0 + 10.0^((r1 - r2) / D1))
    e2 = 1.0 / (1.0 + 10.0^((r2 - r1) / D1))
    
    # Step 2: Calculate raw rating delta
    Δ1 = wm * we * W * (a1 - e1)
    Δ2 = wm * we * W * (a2 - e2)
    
    # Step 3: Centripetal force (based on default and ceiling ratings)
    if Δ1 < 0
        Δ1_prime = Δ1 * (2.0 / (1.0 + 10.0^(-(r1 - r0) / D2)))
    else
        Δ1_prime = Δ1 * (2.0 / (1.0 + 10.0^((r1 - rc) / D2)))
    end
    
    if Δ2 < 0
        Δ2_prime = Δ2 * (2.0 / (1.0 + 10.0^(-(r2 - r0) / D2)))
    else
        Δ2_prime = Δ2 * (2.0 / (1.0 + 10.0^((r2 - rc) / D2)))
    end
    
    # Step 4: Centripetal force (based on opponent's rating)
    if Δ1 < 0
        Δ1_dprime = Δ1_prime * (2.0 / (1.0 + 10.0^(-(r1 - r2) / D3)))
    else
        Δ1_dprime = Δ1_prime * (2.0 / (1.0 + 10.0^((r1 - r2) / D3)))
    end
    
    if Δ2 < 0
        Δ2_dprime = Δ2_prime * (2.0 / (1.0 + 10.0^(-(r2 - r1) / D3)))
    else
        Δ2_dprime = Δ2_prime * (2.0 / (1.0 + 10.0^((r2 - r1) / D3)))
    end
    
    # Step 5: Result of centripetal force
    r1_prime = r1 + Δ1_dprime
    r2_prime = r2 + Δ2_dprime
    
    # Step 6: Long jump
    if r1 < r1_prime && r1_prime < r2
        r1_prime = r1_prime + α * (r2 - r1_prime)
    elseif r1 > r1_prime && r1_prime > r2
        r1_prime = r1_prime + β * (r2 - r1_prime)
    end
    
    if r2 < r2_prime && r2_prime < r1
        r2_prime = r2_prime + α * (r1 - r2_prime)
    elseif r2 > r2_prime && r2_prime > r1
        r2_prime = r2_prime + β * (r1 - r2_prime)
    end
    
    return r1_prime, r2_prime
end