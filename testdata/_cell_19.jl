using Distributions

function calculate_weight(w::Int, l::Int)
    # Use normal distribution with scale parameter adjusted by winner's games
    norm_dist = Normal(0, 2/sqrt(w))
    # Calculate weight using cumulative distribution function
    return 1 - 2 * cdf(norm_dist, -(w-l)/2)
end

function generate_weight_map()
    weight_map = Dict{Tuple{Int,Int}, Float64}()
    for w in 1:9  # Maximum games in a match is typically 9
        for l in 0:(w-1)
            weight_map[(w, l)] = calculate_weight(w, l)
        end
    end
    return weight_map
end

# Generate the weight map at module load time
const WEIGHT_MAP = generate_weight_map()

function result_to_weight(result::String)
    # Split result string and convert to integers
    scores = split(result, ':') .|> x -> parse(Int, x)
    x, y = scores
    
    # Return 0 for draws
    x == y && return 0.0
    
    # Determine winner and loser game counts
    winner_games = max(x, y)
    loser_games = min(x, y)
    
    # Calculate sign based on which player won
    sign_multiplier = x > y ? 1.0 : -1.0
    
    # Look up pre-calculated weight and apply sign
    return WEIGHT_MAP[(winner_games, loser_games)] * sign_multiplier
end