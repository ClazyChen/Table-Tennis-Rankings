#set text(font: ("Times New Roman", "NSimSun"))

= Table Tennis Ranking Calculation
#v(1em)
#h(2em)
As is known to all, the ITTF revised the international ranking rules for table tennis on January 1, 2018. The rules have been controversial since their launch, as the calculation method is too complicated and does not conform to common sense. Under the rules, table tennis players who participate in more competitions can earn more points, rather than better players. Some players have to participate in a large number of competitions in order to maintain their world ranking, which means they loses the opportunity of rest and increases the risk of injury. In addition, the world ranking of players cannot reflect their true level. The probability of the higher-ranked party defeating the lower-ranked party after the ITTF's revised international ranking is only about 66%.

#h(2em)
This project analyzes the data publicly available on the ITTF website, uses the ELO algorithm for point calculation, and makes the following modifications based on the specific characteristics of table tennis:

+ The coefficient is changed according to the level of the competition (see Table 1). This coefficient is my own estimation and has no basis.
 #figure(
    caption: "The coefficient according to the level of the competition",
    table(
      columns: 3,
      [Level], [Competition Types], [Coefficient],
      [1], [Olympic], [2.5],
      [2], [World Championship], [2],
      [3], [World Cup], [1.6],
      [4], [WTT Finals], [1.4],
      [5], [WTT Champions\\WTT Grand Smash\\T2 Diamond], [1.2],
      [6], [WTT Star Contender\\World Tour (Platinum)], [1.1],
      [7], [WTT Contender\\Challenge\\World Tour], [1.0],
      [8], [WTT Feeder\\Continental events], [0.8],
      [9], [Olympic Qualification\\Regional events], [0.5]
    )
  )
  In addition to the Olympic Games, there is an additional 0.8 factor for qualifying matches in other competitions.
  #v(1em)
+ The coefficient is changed according to the score (see Table 2) of the seven games in four or five games in three, etc. It is based on the results of the binomial distribution hypothesis test.
  #figure(
    caption: "The score change factor",
    table(
      columns: 5,
      [Win\\Lose], [0], [1], [2], [3],
      [4], [31/32], [57/64], [99/128], [163/256],
      [3], [15/16], [13/16], [21/32], [],
      [2], [7/8], [11/16], [], [],
      [1], [3/4], [], [], []
    )
  )
  #v(1em)
+ Center return correction. Due to the frequent competition of table tennis players, the ELO points of top players will rise infinitely if without correction, and even if they suffer consecutive losses before retiring, their ELO points cannot be reduced to their actual level. Therefore, an additional correction has been added: the higher the player's points, the lower the rate of increase in points when they win (Logistic distribution), and the higher the rate of decrease in points when they lose. This correction is independent of the opponent's ELO points.
  #v(1em)
+ New face correction. Players who participate in international competitions for the first time always start from an initial score of 1500 and move up in ELO systems. For high-level players (e.g. FAN Zhendong), they will be in a state of having a lower score than their actual ranking for a longer period of time. Therefore, when a novice wins against an opponent with a high ELO score, they can approach the opponent's score proportionally, rather than just receiving the points provided by the ELO algorithm. As the number of matches played increases, this correction will decay exponentially. 
  #v(1em)
+ Dominance correction. Top players (e.g. ZHANG Jike) often receive a high score, and losing some matches has a relatively low impact on them. In order to better measure the dominance of top players, when a high-score player loses to a low-score player, the deducted score will be higher. This correction will further increase when they do not participate in competitions for a long time.

#v(1em)
#h(2em)
The above-mentioned correction has been proven effective in experiments.
My experiment included matches between January 1, 2018 and December 10, 2023. Only players who have played at least five matches in ITTF adult tournaments are included in the statistics. The statistics include 22,253 women's singles matches and 27,334 men's singles matches.
After the correction, the winning rate of high-ranked athletes against low-ranked athletes is about 74% (75.14% for women's singles and 73.42% for men's singles), which is significantly higher than the 66% of the ITTF Rankings.

#v(1em)
The singles ranking is hidden after not participating in ITTF events for one year.

The above settings may cause some retired players (e.g. ZHANG Yining) to still appear in the ranking. Due to uncertainty about whether they have retired, players who meet the following two conditions are marked in gray:
+ Starting from January 1, 2023, no participation in ITTF events.
+ Has not participated in ITTF events within 1 year after the ranking time.

#v(1em)
This model lacks a correction for doubles, so the results of doubles ranking has no practical significance and has a low predictive success rate (68.56% for women's doubles, 66.75% for mixed doubles, and 65.81% for men's doubles, although it is still probably more meaningful than the ITTF ranking). Therefore, this repository does not provide doubles ranking.

#v(3em)
The world ranking as of December 10, 2023 (the end of the Chengdu mixed team) is shown in the attached table. You can see the complete top-128 rankings in _MS-latest.typ_ and _WS-latest.typ_.

#v(3em)
Past world rankings (once a month, starting from January 2004 and statistics taken on the 1st of each month) can be found in this repository, with the top 128 players for both women's singles and men's singles in each ranking. In early rankings, due to insufficient convergence of ELO scores, there may be significant fluctuations in the rankings.

Due to my limited knowledge, most athlete names have not been translated into Chinese. The Chinese translation table can be found in this repository.

For players whose country/region has changed, it is difficult for me to trace the time of their change. All tables show the country/region they represented at the time of their last ITTF competition.

#v(3em)
Thanks to ITTF/WTT, Python, Typst.

Special thanks to Coach EmRatThich. The model proposed by this user provided inspiration for my model.

#pagebreak()
#set text(font: ("Courier New", "NSimSun"))
#figure(
  caption: "Women's Singles (1 - 32)",
    table(
      columns: 4,
      [Ranking], [Player], [Country/Region], [Rating],
      [1], [SUN Yingsha], [CHN], [3714],
      [2], [CHEN Meng], [CHN], [3610],
      [3], [WANG Yidi], [CHN], [3582],
      [4], [WANG Manyu], [CHN], [3571],
      [5], [HAYATA Hina], [JPN], [3522],
      [6], [CHEN Xingtong], [CHN], [3505],
      [7], [SZOCS Bernadette], [ROU], [3470],
      [8], [KIHARA Miyuu], [JPN], [3380],
      [9], [ZHANG Rui], [CHN], [3373],
      [10], [KUAI Man], [CHN], [3342],
      [11], [YANG Xiaoxin], [MON], [3339],
      [12], [HIRANO Miu], [JPN], [3338],
      [13], [ITO Mima], [JPN], [3328],
      [14], [HE Zhuojia], [CHN], [3321],
      [15], [FAN Siqi], [CHN], [3305],
      [16], [QIAN Tianyi], [CHN], [3295],
      [17], [HAN Ying], [GER], [3281],
      [18], [OJIO Haruna], [JPN], [3266],
      [19], [HARIMOTO Miwa], [JPN], [3262],
      [20], [LIU Weishan], [CHN], [3251],
      [21], [CHEN Yi], [CHN], [3246],
      [22], [ISHIKAWA Kasumi], [JPN], [3243],
      [23], [JEON Jihee], [KOR], [3224],
      [24], [CHENG I-Ching], [TPE], [3205],
      [25], [SHIN Yubin], [KOR], [3184],
      [26], [DIAZ Adriana], [PUR], [3181],
      [27], [SHAN Xiaona], [GER], [3164],
      [28], [SATO Hitomi], [JPN], [3151],
      [29], [NAGASAKI Miyu], [JPN], [3146],
      [30], [SHI Xunyao], [CHN], [3143],
      [31], [JOO Cheonhui], [KOR], [3132],
      [32], [ANDO Minami], [JPN], [3104],
    )
  )

#pagebreak()
#figure(
  caption: "Men's Singles (1 - 32)",
    table(
      columns: 4,
      [Ranking], [Player], [Country/Region], [Rating],
      [1], [WANG Chuqin], [CHN], [3622],
      [2], [MA Long], [CHN], [3595],
      [3], [FAN Zhendong], [CHN], [3592],
      [4], [LIN Yun-Ju], [TPE], [3580],
      [5], [LIANG Jingkun], [CHN], [3513],
      [6], [LIN Gaoyuan], [CHN], [3513],
      [7], [ZHOU Qihao], [CHN], [3439],
      [8], [LEBRUN Felix], [FRA], [3433],
      [9], [HARIMOTO Tomokazu], [JPN], [3392],
      [10], [TANAKA Yuta], [JPN], [3391],
      [11], [MOREGARD Truls], [SWE], [3391],
      [12], [LIN Shidong], [CHN], [3373],
      [13], [CALDERANO Hugo], [BRA], [3351],
      [14], [TOGAMI Shunsuke], [JPN], [3339],
      [15], [QIU Dang], [GER], [3331],
      [16], [JANG Woojin], [KOR], [3326],
      [17], [FALCK Mattias], [SWE], [3291],
      [18], [SUN Wen], [CHN], [3282],
      [19], [BOLL Timo], [GER], [3278],
      [20], [OVTCHAROV Dimitrij], [GER], [3267],
      [21], [XIANG Peng], [CHN], [3262],
      [22], [MENGEL Steffen], [GER], [3259],
      [23], [LIU Dingshuo], [CHN], [3257],
      [24], [LIM Jonghoon], [KOR], [3256],
      [25], [GROTH Jonathan], [DEN], [3246],
      [26], [FREITAS Marcos], [POR], [3216],
      [27], [CHO Daeseong], [KOR], [3213],
      [28], [FRANZISKA Patrick], [GER], [3212],
      [29], [AN Jaehyun], [KOR], [3211],
      [30], [ARUNA Quadri], [NGR], [3202],
      [31], [ZHOU Kai], [CHN], [3199],
      [32], [JORGIC Darko], [SLO], [3196],
    )
  )