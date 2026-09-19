using JSON
using Dates

struct Match
    player_a_id::Int
    player_x_id::Int
    player_a_assoc::String
    player_x_assoc::String
    weight::Float32
    result::String
    games::String
end

struct Event
    id::Int
    name::String
    weight::Float32
    time::Date
    match::Vector{Match}
end

struct Player
    id::Int
    name::String
    sex::String
    history::Dict{String, Date}
    yob::Int
    hand::String
    style::String
    grip::String
end