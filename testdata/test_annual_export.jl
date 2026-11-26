using JSON
using Dates

const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "src", "structures.jl"))
include(joinpath(ROOT, "src", "rating.jl"))
include(joinpath(ROOT, "src", "typst_output.jl"))
include(joinpath(ROOT, "src", "web_export.jl"))
include(joinpath(ROOT, "src", "annual_export.jl"))

function annual_test_player(id::Int)
    return Player(id, "Player $id", "M", Dict("CHN" => Date("2000-01-01")),
                  1990, "Right-Hand", "ShakeHand", "Attack")
end

function annual_test_match(a::Int, x::Int)
    return Match(a, x, "CHN", "CHN", 1.0f0, "3:0", "11:5 11:5 11:5")
end

players = Dict{Int,Player}(id => annual_test_player(id) for id in 1:5)
c = WebExportCollector()
c.months = [Dates.format(d, "yyyy-mm") for d in Date("2025-01-01"):Month(1):Date("2026-11-01")]

for (pid, rating) in ((1, 3000), (2, 3200), (3, 3100), (4, 3300))
    c.series[pid] = [Int[month_index(Date(2025, m, 1)) + 1, rating] for m in 1:12]
    c.final_ratings[pid] = Float64(rating)
end
current_mi = month_index(Date("2026-11-26"))
c.series[5] = [Int[mi, 3000] for mi in current_mi - 10:current_mi]
c.final_ratings[5] = 3000.0
c.latest_rows["MS"] = Any[Any[1, 5, 3000, "NEW", 36, "CHN", "R", "S", "A"]]

events = Dict{Date,Vector{Event}}()
event_id = 0
for (pid, dates) in ((1, ["2025-01-15", "2025-03-15", "2025-07-15"]),
                     (2, ["2025-01-20", "2025-04-20"]),
                     (3, ["2025-02-15"]),
                     (5, ["2026-01-15", "2026-03-15"]))
    for date_string in dates
        date = Date(date_string)
        global event_id += 1
        event = Event(event_id, "Test $event_id", 1.0f0, date,
                      [annual_test_match(pid, 999)])
        push!(get!(() -> Event[], events, date), event)
    end
end

@assert annual_score(3200) == 100.0
@assert annual_score(3000) == 90.0
@assert annual_score(3300) == 100.0
@assert annual_score(1000) == 0.0

mktempdir() do out_dir
    export_annual_web_data(c, events, players; out_dir=out_dir,
                           as_of=Date("2026-11-26"))
    rows = JSON.parsefile(joinpath(out_dir, "annual", "MS-2025.json"))
    @assert length(rows) == 3
    @assert [row[2] for row in rows] == [2, 1, 3]
    @assert [row[3] for row in rows] == [95.0, 90.0, 85.0]
    @assert [row[4] for row in rows] == [2, 3, 1]
    @assert [row[8] for row in rows] == [100, 0, 200]
    @assert all(row[2] != 4 for row in rows)

    rolling = JSON.parsefile(joinpath(out_dir, "annual", "MS-current.json"))
    @assert length(rolling) == 1
    @assert rolling[1][2] == 5
    @assert rolling[1][3] == 85.0
    @assert rolling[1][4] == 2
    @assert rolling[1][7] == 3000.0

    index = JSON.parsefile(joinpath(out_dir, "annual-index.json"))
    @assert index["years"] == [2025]
    @assert !haskey(index, "current_year")
    @assert !isfile(joinpath(out_dir, "annual", "MS-2026.json"))
end
