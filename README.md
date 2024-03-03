<h1>Table Tennis Rankings</h1>

This repository demonstrates an excellent table tennis international ranking algorithm that better reflects the actual competitive level of table tennis players compared to the simple ELO algorithm and the new ranking method used by ITTF after January 1, 2018. The algorithm uses data provided on the ITTF official website and is modified based on the ELO algorithm to make the results more consistent with the situation of table tennis.

<b>The accuracy of the models in this repository for predicting women's singles matches is 76.16%, and for men's singles matches is 73.93%</b>, far higher than the international ranking of the ITTF.

This repository provides world rankings from January 2004 to December 2023 (the first day of each month is used as the ranking time node). Earlier rankings cannot be calculated because the ITTF does not provide relevant data.
All rankings use Typst, which you can easily convert to pdf files.

This repository includes men's singles ranking and women's singles ranking. You can see the changes of top players in the past twenty years: from Wang Liqin, Ma Lin, Wang Hao, Zhang Jike, Ma Long, Fan Zhendong to Wang Chuqin; from Zhang Yining, Guo Yue, Li Xiaoxia, Ding Ning, Liu Shiwen, Chen Meng to Sun Yingsha.

For detailed description of the algorithm and latest rankings, please refer to introduction.pdf.

You are welcome to provide suggestions for improving the algorithm model or the display form of the ranking.


<h1>乒乓球排名</h1>

这个仓库展示了一种优秀的乒乓球国际排名算法，相比于简单的ELO算法和ITTF在2018年1月1日之后使用的新排名方法，该算法能够更好地反映乒乓球运动员的实际竞技水平。算法采用了ITTF官网上提供的数据，在ELO算法的算法的基础上进行了修正，使结果更符合乒乓球运动的情况。

<b>这个仓库中的模型预测女单比赛的正确率为 76.16%，男单比赛的正确率为 73.93%</b>，远高于ITTF的国际排名。

这个仓库提供从2004年1月至2023年12月的世界排名（每个月的第一天作为排名的时间节点）。更早的排名无法计算，因为ITTF没有提供相关数据。
所有的排名均使用Typst，您可以很方便地将其转换为pdf文件。

这个仓库包括男子单打排名和女子单打排名。您可以看到二十年的顶级运动员变化：从王励勤，马琳，王皓，张继科，马龙，樊振东到王楚钦；从张怡宁，郭跃，李晓霞，丁宁，刘诗雯，陈梦到孙颖莎。

算法的详细说明和最新排名参见 introduction_CN.pdf。

欢迎您对算法模型或者排名的展示形式提出改进意见。

<h1>Update Steps</h1>

+ Download new events and matches data from ITTF official website.
+ run `events_profile.py` to generate the profile of events.
+ run `matches_profile.py` to generate the profile of matches.
+ run `elo_preparation.py` for preprocessing.
+ run `elo.py` (WS / MS / WD / MD / XD) to generate all-time rankings.
+ run `translate.py` to translate the rankings to Chinese.