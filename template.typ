#let left = {
  set text(color.rgb(0xc0, 0x40, 0x40))
  [left]
}
#let right = {
  set text(color.rgb(0x40, 0x90, 0x40))
  [right]
}
#let shakehand = {
  set text(color.rgb(0x40, 0x40, 0xc0))
  [shakehand]
}
#let penhold = {
  set text(color.rgb(0xc0, 0x20, 0xc0))
  [penhold]
}
#let attack = {
  set text(color.rgb(0xff, 0x90, 0x90))
  [attack]
}
#let defense = {
  set text(color.rgb(0x00, 0xc0, 0xc0))
  [defense]
}
#let age(n) = {
  if n <= 12 { set text(color.rgb(0x40, 0xb0 + 4*(12 - n), 0)); [*#n*]}
  if 12 < n and n <= 26 { set text(color.rgb(0x40 + 8*(n - 12), 0xb0, 0)); [*#n*]}
  if 26 < n and n <= 40 { set text(color.rgb(0xb0, 0xb0 - 8*(n - 26), 0)); [*#n*]}
  if n > 40 { set text(color.rgb(0xb0 + 2*(n - 40), 0x40 - 2*(n - 40), 0)); [*#n*]}
}
#let delta(n) = {
  if n > 0 { set text(color.rgb(0x40, 0xc0, 0x40)); [*▲#n*] }
  if n == 0 { [-] }
  if n < 0 { set text(color.rgb(0xf0, 0x40, 0x40)); [*▼#(-n)*] }
}
#let assoc(str) = {
  set text(font: ("Cascadia Mono"))
  if str == "AIN" { [#str] }
  else if str == "?" { [#str] }
  else {
    [#str #box(image("data/flags/" + str + ".png", height: 10pt), baseline: 1pt)]
  }
}
#let name(str) = {
  set text(font: ("Cascadia Mono", "Microsoft YaHei"))
  [#str]
}