# Check if an event is a youth event
function is_youth(name::String)
    youth_patterns = [
        "Youth", "youth",
        "Cadet", "cadet",
        "Junior", "junior",
        "U21", "U-21", "YOG",
        "U15", "U-15",
        "U18", "U-18"
    ]
    return any(pattern -> occursin(pattern, name), youth_patterns)
end

# Helper function to check if event is Asian/European
function is_major_continental(name::String)
    return any(region -> occursin(region, name), ["Asian", "European", "Asia", "Europe"])
end

# Pattern matching for different event types
function match_weight(::Val{:Olympic_Games}, name::String)
    if occursin("Qualification", name) || occursin("Road", name)
        return 0.2
    elseif is_youth(name)
        return 1.0
    else
        return 3.0
    end
end

function match_weight(::Val{:Youth_Olympic_Games}, name::String)
    return 1.0
end

function match_weight(::Val{:Youth_Olympic_Games_Qualification}, name::String)
    return 0.2
end

function match_weight(::Val{:WTTC}, name::String)
    return 2.5
end

function match_weight(::Val{:ITTF_WTTC}, name::String)
    return 2.5
end

function match_weight(::Val{:World_Cup}, name::String)
    return 2.0
end

function match_weight(::Val{:ITTF_World_Cup}, name::String)
    return 2.0
end

function match_weight(::Val{:WTT_Finals}, name::String)
    return 1.5
end

function match_weight(::Val{:World_Tour__Pro_Tour}, name::String)
    if occursin("Finals", name)
        return 1.5
    elseif occursin("Platinum", name)
        return 1.3
    else
        return 1.2
    end
end

function match_weight(::Val{:ITTF_World_Tour__Pro_Tour}, name::String)
    if occursin("Finals", name)
        return 1.5
    elseif occursin("Platinum", name)
        return 1.3
    else
        return 1.2
    end
end

function match_weight(::Val{:WTT_Champions}, name::String)
    return 1.3
end

function match_weight(::Val{:WTT_Grand_Smash}, name::String)
    return 1.4
end

function match_weight(::Val{:WTT_Youth_Grand_Smash}, name::String)
    return 0.5
end

function match_weight(::Val{:Continental_Games}, name::String)
    if is_youth(name)
        return 0.25
    else
        return is_major_continental(name) ? 1.6 : 0.8
    end
end

function match_weight(::Val{:Continental}, name::String)
    if is_youth(name)
        return is_major_continental(name) ? 0.5 : 0.25
    else
        return is_major_continental(name) ? 1.5 : 0.75
    end
end

function match_weight(::Val{:WTT_Contender_Series}, name::String)
    return occursin("Star", name) ? 1.2 : 1.1
end

function match_weight(::Val{:T2_Diamond}, name::String)
    return 1.0
end

function match_weight(::Val{:WJTTC}, name::String)
    return 0.8
end

function match_weight(::Val{:ITTF_WJTTC}, name::String)
    return 0.8
end

function match_weight(::Val{:Challenge}, name::String)
    return occursin("Plus", name) ? 1.1 : 1.0
end

function match_weight(::Val{:ITTF_Challenge}, name::String)
    return occursin("Plus", name) ? 1.1 : 1.0
end

function match_weight(::Val{:Olympic_Qualification}, name::String)
    return 0.6
end

function match_weight(::Val{:World_Youth_Championships}, name::String)
    return 0.8
end

function match_weight(::Val{:World_Cadet_Challenge}, name::String)
    return 0.65
end

function match_weight(::Val{:World_Junior_Circuit}, name::String)
    if occursin("Finals", name)
        return 0.5
    elseif occursin("Platinum", name) || occursin("Golden", name)
        return 0.4
    else
        return 0.3
    end
end

function match_weight(::Val{:ITTF_World_Youth_Championships}, name::String)
    return 0.8
end

function match_weight(::Val{:ITTF_World_Cadet_Challenge}, name::String)
    return 0.65
end

function match_weight(::Val{:ITTF_World_Junior_Circuit}, name::String)
    if occursin("Finals", name)
        return 0.5
    elseif occursin("Platinum", name) || occursin("Golden", name)
        return 0.4
    else
        return 0.3
    end
end

function match_weight(::Val{:WTT_Feeder_Series}, name::String)
    return 1.0
end

function match_weight(::Val{:Multi_sport_events}, name::String)
    # Asian Games special cases
    if occursin("Asian", name) && (occursin("Guangzhou", name) || occursin("Incheon", name))
        return 1.6
    elseif occursin("Pan American", name) && occursin("Guadalajara", name)
        return 0.8
    elseif is_youth(name)
        return 0.2
    else
        return 0.6
    end
end

function match_weight(::Val{:Other_events}, name::String)
    if occursin("Open,", name)
        return is_youth(name) ? 0.3 : 1.0
    elseif occursin("WTTC", name)  # WTTC qualification
        return 0.5
    elseif occursin("Top 10", name)  # European Youth Top 10
        return 0.5
    else
        return is_youth(name) ? 0.2 : 0.6
    end
end

function match_weight(::Val{:WTT_Youth_Contender_Series}, name::String)
    return occursin("Star", name) ? 0.4 : 0.3
end

# Fallback for unknown event types
function match_weight(::Val, name::String)
    return 0.1
end

# Main weight calculation function
function weight(type_::String, name::String)
    # Special cases first
    if occursin("China vs World Team", name) || occursin("China vs. World Team", name)
        return 1.2
    elseif occursin("Tournament of Champions", name)
        return 1.5
    end

    # Convert type string to symbol, replacing spaces and special characters
    type_symbol = Symbol(replace(type_, " " => "_", "/" => ""))
    
    # Main weight calculation using pattern matching
    return match_weight(Val(type_symbol), name)
end