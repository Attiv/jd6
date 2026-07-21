import re
import os
import urllib.request
import jieba
from collections import Counter

def download_file(url, save_path):
    """从URL下载文件到指定路径"""
    try:
        print(f"正在从 {url} 下载文件...")
        urllib.request.urlretrieve(url, save_path)
        print(f"下载完成，已保存到 {save_path}")
        return True
    except Exception as e:
        print(f"下载失败: {e}")
        return False

def load_file_to_set(file_path, encoding='utf-8'):
    """加载文件内容到集合中"""
    word_set = set()
    try:
        with open(file_path, 'r', encoding=encoding) as f:
            for line in f:
                parts = line.strip().split()
                if parts:
                    word = parts[0]  # 第一部分是词
                    word_set.add(word)
        print(f"从 {file_path} 加载了 {len(word_set)} 个词条")
        return word_set
    except Exception as e:
        print(f"加载文件失败: {e}")
        return set()

def download_jieba_dict():
    """下载结巴分词的词典文件"""
    jieba_dict_url = "https://raw.githubusercontent.com/fxsjy/jieba/master/jieba/dict.txt"
    jieba_dict_path = "jieba_dict.txt"
    
    if not os.path.exists(jieba_dict_path):
        success = download_file(jieba_dict_url, jieba_dict_path)
        if not success:
            print("下载结巴词典失败，将使用其他词库")
            return set()
    
    # 加载结巴词典
    jieba_words = set()
    try:
        with open(jieba_dict_path, 'r', encoding='utf-8') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    word = parts[0]
                    freq = int(parts[1])
                    if len(word) >= 2 and freq > 1000:  # 只保留长度>=2且词频较高的词
                        jieba_words.add(word)
        print(f"从结巴词典中提取了 {len(jieba_words)} 个常用词")
        return jieba_words
    except Exception as e:
        print(f"处理结巴词典失败: {e}")
        return set()

def download_common_words():
    """下载常用词汇表"""
    print("正在准备常用词汇...")
    
    # 获取结巴词典中的常用词
    jieba_dict_words = download_jieba_dict()
    
    # 下载停用词表 (用于参考常用词)
    stopwords_url = "https://raw.githubusercontent.com/goto456/stopwords/master/cn_stopwords.txt"
    stopwords_path = "cn_stopwords.txt"
    if not os.path.exists(stopwords_path):
        download_file(stopwords_url, stopwords_path)
    
    # 加载停用词表中的词 (实际上这些是常用词)
    stopwords = load_file_to_set(stopwords_path)
    
    # 合并词表
    common_words = jieba_dict_words.union(stopwords)
    
    # 添加日常常用词
    daily_common_words = """
    的 一 是 在 不 了 有 和 人 这 中 大 为 上 个 国 我 以 要 他
    时 来 用 们 生 到 作 地 于 出 就 分 对 成 会 可 主 发 年 动
    同 工 也 能 下 过 子 说 产 种 面 而 方 后 多 定 行 学 法 所
    民 得 经 十 三 之 进 着 等 部 度 家 电 力 里 如 水 化 高 自
    二 理 起 小 物 现 实 加 量 都 两 体 制 机 当 使 点 从 业 本
    去 把 性 好 应 开 它 合 还 因 由 其 些 然 前 外 天 政 四 日
    那 社 义 事 平 形 相 全 表 间 样 与 关 各 重 新 线 内 数 正
    心 反 你 明 看 原 又 么 利 比 或 但 质 气 第 向 道 命 此 变
    条 只 没 结 解 问 意 建 月 公 无 系 军 很 情 者 最 立 代 想
    已 通 并 提 直 题 党 程 展 五 果 料 象 员 革 位 入 常 文 总
    次 品 式 活 设 及 管 特 件 长 求 老 头 基 资 边 流 路 级 少
    图 山 统 接 知 较 将 组 见 计 别 她 手 角 期 根 论 运 农 指
    几 九 区 强 放 决 西 被 干 做 必 战 先 回 则 任 取 据 处 队
    南 给 色 光 门 即 保 治 北 造 百 规 热 领 七 海 口 东 导 器
    压 志 世 金 增 争 济 阶 油 思 术 极 交 受 联 什 认 六 共 权
    收 证 改 清 美 再 采 转 更 单 风 切 打 白 教 速 花 带 安 场
    身 车 例 真 务 具 万 每 目 至 达 走 积 示 议 声 报 斗 完 类
    八 离 华 名 确 才 科 张 信 马 节 话 米 整 空 元 况 今 集 温
    传 土 许 步 群 广 石 记 需 段 研 界 拉 林 律 叫 且 究 观 越
    织 装 影 算 低 持 音 众 书 布 复 容 儿 须 际 商 非 验 连 断
    深 难 近 矿 千 周 委 素 技 备 半 办 青 省 列 习 响 约 支 般
    史 感 劳 便 团 往 酸 历 市 克 何 除 消 构 府 称 太 准 精 值
    号 率 族 维 划 选 标 写 存 候 毛 亲 快 效 斯 院 查 江 型 眼
    王 按 格 养 易 置 派 层 片 始 却 专 状 育 厂 京 识 适 属 圆
    包 火 住 调 满 县 局 照 参 红 细 引 听 该 铁 价 严 首 底 液
    官 德 随 病 苏 失 尔 死 讲 配 女 黄 推 显 谈 罪 神 艺 呢 席
    含 企 望 密 批 营 项 防 举 球 英 氧 势 告 李 台 落 木 帮 轮
    破 亚 师 围 注 远 字 材 排 供 河 态 封 另 施 减 树 溶 怎 止
    案 言 士 均 武 固 叶 鱼 波 视 仅 费 紧 爱 左 章 早 朝 害 续
    轻 服 试 食 充 兵 源 判 护 司 足 某 练 差 致 板 田 降 黑 犯
    负 击 范 继 兴 似 余 坚 曲 输 修 故 城 夫 够 送 笔 船 占 右
    财 吃 富 春 职 觉 汉 画 功 巴 跟 虽 杂 飞 检 吸 助 升 阳 互
    初 创 抗 考 投 坏 策 古 径 换 未 跑 留 钢 曾 端 责 站 简 述
    钱 副 尽 帝 射 草 冲 承 独 令 限 阿 宣 环 双 请 超 微 让 控
    州 良 轴 找 否 纪 益 依 优 顶 础 载 倒 房 突 坐 粉 敌 略 客
    袁 冷 胜 绝 析 块 剂 测 丝 协 诉 念 陈 仍 罗 盐 友 洋 错 苦
    夜 刑 移 频 逐 靠 混 母 短 皮 终 聚 汽 村 云 哪 既 距 卫 停
    烈 央 察 烧 迅 境 若 印 洲 刻 括 激 孔 搞 甚 室 待 核 校 散
    侵 吧 甲 游 久 菜 味 旧 模 湖 货 损 预 阻 毫 普 稳 乙 妈 植
    息 扩 银 语 挥 酒 守 拿 序 纸 医 缺 雨 吗 针 刘 啊 急 唱 误
    训 愿 审 附 获 茶 鲁 予 戏 细 瞧 负 尽 春 暗 徐 鱼 必 鸡 之
    """
    for word in daily_common_words.split():
        if word.strip():
            common_words.add(word.strip())
    
    # 还可以增加一些行业术语等
    industry_terms = """
    计算机 软件 硬件 编程 程序 网络 互联网 大数据 人工智能 
    机器学习 深度学习 神经网络 算法 数据库 云计算 区块链
    手机 电脑 平板 智能 设备 电子 芯片 半导体 显卡 内存
    教育 学习 培训 考试 学校 大学 高中 初中 小学 幼儿园
    医疗 医院 医生 护士 疾病 药物 治疗 康复 手术 病毒
    金融 银行 股票 基金 保险 理财 投资 贷款 信用卡 支付
    """
    for word in industry_terms.split():
        if word.strip():
            common_words.add(word.strip())
    
    print(f"总共收集了 {len(common_words)} 个常用词")
    return common_words

def download_famous_people():
    """准备著名人物名单"""
    print("正在准备著名人物名单...")
    
    # 添加一些著名人物的姓名
    famous_people = set()
    
    politicians = """
    毛泽东 邓小平 周恩来 朱德 刘少奇 李大钊 孙中山 袁世凯 蒋介石 宋庆龄
    陈独秀 李鸿章 孙权 曹操 刘备 关羽 张飞 诸葛亮 司马懿 赵匡胤
    朱元璋 王安石 李世民 成吉思汗 忽必烈 康熙 雍正 乾隆 慈禧
    秦始皇 汉武帝 唐太宗 武则天 朱棣 华国锋 胡耀邦 赵紫阳 
    江泽民 胡锦涛 习近平 李克强 温家宝 朱镕基 李鹏
    """
    for name in politicians.split():
        if name.strip():
            famous_people.add(name.strip())
    
    writers = """
    鲁迅 老舍 巴金 茅盾 郭沫若 钱钟书 沈从文 张爱玲 金庸 古龙
    琼瑶 余华 莫言 王小波 韩寒 龙应台 席慕蓉 三毛 冰心 林语堂
    苏轼 李白 杜甫 白居易 王维 李清照 杜牧 辛弃疾 陆游 柳宗元
    曹雪芹 吴承恩 施耐庵 罗贯中 蒲松龄 孔子 老子 庄子 孟子 墨子
    """
    for name in writers.split():
        if name.strip():
            famous_people.add(name.strip())
    
    scientists = """
    钱学森 邓稼先 华罗庚 陈景润 李政道 杨振宁 袁隆平 屠呦呦 吴健雄
    李四光 竺可桢 茅以升 赵九章 张衡 祖冲之 沈括 黄道婆 毕升
    """
    for name in scientists.split():
        if name.strip():
            famous_people.add(name.strip())
    
    entertainers = """
    成龙 李连杰 周星驰 周杰伦 刘德华 张学友 王菲 梁朝伟 张国荣 黎明
    郭富城 刘若英 李宇春 汪峰 谢霆锋 章子怡 巩俐 范冰冰 李小龙 周润发
    葛优 姜文 徐峥 沈腾 黄渤 章子怡 李冰冰 赵薇 周迅 姚明
    林丹 易建联 李娜 刘翔 孙杨 郎平 丁俊晖 谷爱凌 李宁 马龙
    """
    for name in entertainers.split():
        if name.strip():
            famous_people.add(name.strip())
    
    business = """
    马云 马化腾 李彦宏 王健林 刘强东 任正非 雷军 董明珠 柳传志 丁磊
    李嘉诚 杨致远 张瑞敏 宗庆后 王石 牛根生 张朝阳 俞敏洪 王传福 稻盛和夫
    """
    for name in business.split():
        if name.strip():
            famous_people.add(name.strip())
    
    print(f"总共收集了 {len(famous_people)} 个著名人物名")
    return famous_people

def extract_chinese_word(line):
    """从词典行中提取中文词语"""
    parts = re.split(r'\s+', line.strip(), 1)
    if len(parts) > 0:
        return parts[0]
    return ""

def process_dictionary(input_file, output_file, common_words, famous_people):
    """处理词典文件，保留常用词和著名人物姓名"""
    print(f"处理文件: {input_file}")
    
    total_lines = 0
    kept_lines = 0
    header_lines = []
    collecting_header = True
    
    with open(input_file, 'r', encoding='utf-8') as infile, open(output_file, 'w', encoding='utf-8') as outfile:
        for line in infile:
            total_lines += 1
            
            # 处理文件头部
            if collecting_header:
                if line.startswith('##') or line.startswith('---'):
                    header_lines.append(line)
                    outfile.write(line)
                    continue
                else:
                    collecting_header = False
            
            # 跳过空行或者特殊格式行
            if not line.strip() or line.startswith('#') or line.startswith('---'):
                outfile.write(line)
                kept_lines += 1
                continue
            
            # 提取中文词语
            word = extract_chinese_word(line)
            if not word:
                continue
                
            # 检查是否为常用词或著名人物
            if word in common_words or word in famous_people:
                outfile.write(line)
                kept_lines += 1
            # 额外的检查：如果是2-3个字的词，用jieba分词检查组成部分是否都是常用词
            elif 2 <= len(word) <= 3:
                parts = jieba.lcut(word)
                if all(part in common_words for part in parts):
                    outfile.write(line)
                    kept_lines += 1
            # 保留单字
            elif len(word) == 1:
                outfile.write(line)
                kept_lines += 1
    
    print(f"总行数: {total_lines}")
    print(f"保留行数: {kept_lines}")
    print(f"删除行数: {total_lines - kept_lines}")
    print(f"过滤结果已保存到: {output_file}")

def main():
    # 获取输入文件路径
    input_file = input("请输入词典文件路径 (按Enter使用默认文件 'xmjd6.fjcy.dict.yaml'): ").strip()
    if not input_file:
        input_file = "xmjd6.fjcy.dict.yaml"
    
    if not os.path.exists(input_file):
        print(f"错误: 文件 '{input_file}' 不存在!")
        return
    
    # 设置输出文件路径
    output_file = input_file.rsplit('.', 1)[0] + "_filtered.txt"
    output_path = input(f"请输入输出文件路径 (按Enter使用默认路径 '{output_file}'): ").strip()
    if output_path:
        output_file = output_path
    
    # 下载词库
    common_words = download_common_words()
    famous_people = download_famous_people()
    
    # 处理词典
    process_dictionary(input_file, output_file, common_words, famous_people)

if __name__ == "__main__":
    main()