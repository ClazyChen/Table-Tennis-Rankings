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
+ Dominance correction. Top players (e.g. ZHANG Jike) often receive a high score, and losing some matches has a relatively low impact on them. In order to better measure the dominance of top players, when a high-score player loses to a low-score player, the deducted score will be higher. 
// This correction will further increase when they do not participate in competitions for a long time.

#v(1em)
#h(2em)
The above-mentioned correction has been proven effective in experiments.
My experiment included matches between January 1, 2018 and December 10, 2023. Only players who have played at least five matches in ITTF adult events are included in the statistics. The statistics include 22,253 women's singles matches and 27,334 men's singles matches.
After the correction, the winning rate of high-ranked athletes against low-ranked athletes is about 75% (76.28% for women's singles and 73.91% for men's singles), which is significantly higher than the 66% of the ITTF Rankings.

#v(1em)
The singles ranking is hidden after not participating in ITTF events for one year.

The above settings may cause some retired players (e.g. ZHANG Yining) to still appear in the ranking. Due to uncertainty about whether they have retired, players who meet the following two conditions are marked in gray:
+ Starting from one year ago, no participation in ITTF events.
+ Has not participated in ITTF events within 1 year after the ranking time.

#v(1em)
This model lacks a correction for doubles, so the results of doubles ranking has no practical significance and has a low predictive success rate (68.56% for women's doubles, 66.75% for mixed doubles, and 65.81% for men's doubles, although it is still probably more meaningful than the ITTF ranking). Therefore, this repository does not provide doubles ranking.

#v(3em)
The world ranking as of Feburary 25th (the end of the Busan WTTC Finals) is shown in the attached table. You can see the complete top-128 rankings in _MS-latest.typ_ and _WS-latest.typ_.

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
      [1], [SUN Yingsha], [CHN], [3841],
      [2], [CHEN Meng], [CHN], [3581],
      [3], [WANG Manyu], [CHN], [3567],
      [4], [HAYATA Hina], [JPN], [3482],
      [5], [CHEN Xingtong], [CHN], [3466],
      [6], [WANG Yidi], [CHN], [3441],
      [7], [HIRANO Miu], [JPN], [3404],
      [8], [CHENG I-Ching], [TPE], [3403],
      [9], [HE Zhuojia], [CHN], [3372],
      [10], [ITO Mima], [JPN], [3356],
      [11], [QIAN Tianyi], [CHN], [3356],
      [12], [ZHANG Rui], [CHN], [3339],
      [13], [KIHARA Miyuu], [JPN], [3333],
      [14], [JEON Jihee], [KOR], [3321],
      [15], [KUAI Man], [CHN], [3318],
      [16], [FAN Siqi], [CHN], [3314],
      [17], [SZOCS Bernadette], [ROU], [3312],
      [18], [HARIMOTO Miwa], [JPN], [3309],
      [19], [ISHIKAWA Kasumi], [JPN], [3266],
      [20], [MITTELHAM Nina], [GER], [3264],
      [21], [SHI Xunyao], [CHN], [3264],
      [22], [HAN Ying], [GER], [3250],
      [23], [LIU Weishan], [CHN], [3239],
      [24], [CHEN Yi], [CHN], [3232],
      [25], [YANG Xiaoxin], [MON], [3222],
      [26], [OJIO Haruna], [JPN], [3219],
      [27], [NAGASAKI Miyu], [JPN], [3193],
      [28], [DIAZ Adriana], [PUR], [3187],
      [29], [JOO Cheonhui], [KOR], [3161],
      [30], [MORI Sakura], [JPN], [3160],
      [31], [POLCANOVA Sofia], [AUT], [3152],
      [32], [ANDO Minami], [JPN], [3149],
    )
  )

#pagebreak()
#figure(
  caption: "Men's Singles (1 - 32)",
    table(
      columns: 4,
      [Ranking], [Player], [Country/Region], [Rating],
      [1], [WANG Chuqin], [CHN], [3754],
      [2], [FAN Zhendong], [CHN], [3735],
      [3], [MA Long], [CHN], [3546],
      [4], [LIANG Jingkun], [CHN], [3520],
      [5], [LEBRUN Felix], [FRA], [3516],
      [6], [LIN Gaoyuan], [CHN], [3512],
      [7], [LIN Yun-Ju], [TPE], [3450],
      [8], [HARIMOTO Tomokazu], [JPN], [3405],
      [9], [JANG Woojin], [KOR], [3395],
      [10], [LIN Shidong], [CHN], [3393],
      [11], [ZHOU Qihao], [CHN], [3370],
      [12], [CALDERANO Hugo], [BRA], [3366],
      [13], [BOLL Timo], [GER], [3339],
      [14], [TANAKA Yuta], [JPN], [3333],
      [15], [TOGAMI Shunsuke], [JPN], [3328],
      [16], [LEE Sang Su], [KOR], [3314],
      [17], [QIU Dang], [GER], [3313],
      [18], [LIM Jonghoon], [KOR], [3311],
      [19], [JORGIC Darko], [SLO], [3306],
      [20], [FREITAS Marcos], [POR], [3305],
      [21], [MOREGARD Truls], [SWE], [3304],
      [22], [GERASSIMENKO Kirill], [KAZ], [3281],
      [23], [WONG Chun Ting], [HKG], [3258],
      [24], [XIANG Peng], [CHN], [3251],
      [25], [GROTH Jonathan], [DEN], [3249],
      [26], [OVTCHAROV Dimitrij], [GER], [3248],
      [27], [MATSUSHIMA Sora], [JPN], [3247],
      [28], [SUN Wen], [CHN], [3247],
      [29], [MENGEL Steffen], [GER], [3225],
      [30], [GAUZY Simon], [FRA], [3219],
      [31], [OH Junsung], [KOR], [3214],
      [32], [LIU Dingshuo], [CHN], [3212],
    )
  )