function translate(src, dst)
    # 读取源文件内容
    text = read(src, String)
    
    # 定义翻译字典
    translation = Dict(
        "Player" => "运动员",
        "Assoc." => "协会",
        "Rating" => "积分",
        "template.typ" => "template_CN.typ",
        "Hand" => "手",
        "Grip" => "握拍",
        "Style" => "削球",
        "Age" => "年龄"
    )
    
    # 从翻译文件中读取更多翻译
    if isfile("translate.txt")
        open("translate.txt", "r") do f
            for line in eachline(f)
                words = split(line, ",")
                if length(words) >= 2
                    translation[strip(words[1])] = strip(words[2])
                end
            end
        end
    end
    
    # 替换文本中的单词
    for (eng, chn) in translation
        text = replace(text, eng * "]" => chn * "]")
        text = replace(text, eng * "\"" => chn * "\"")
    end
    
    # 写入目标文件
    write(dst, text)
end

# 创建中文历史文件夹
for year in 2004:2026
    dir_name = "history/$year"
    cn_dir_name = "history_CN/$year"
    
    if !isdir(cn_dir_name)
        mkdir(cn_dir_name)
    end
    
    # 翻译该年份下的所有文件
    if isdir(dir_name)
        for file_name in readdir(dir_name)
            file_path = "$dir_name/$file_name"
            cn_file_path = "$cn_dir_name/$file_name"
            translate(file_path, cn_file_path)
            println("已翻译 $file_path")
        end
    end
end

# 翻译最新排名文件
for event in ["MS", "WS"]
    translate("$event-latest.typ", "$event-latest_CN.typ")
end

println("翻译完成")
