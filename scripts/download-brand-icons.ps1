#Requires -Version 7
<#
  下载品牌图标并生成图标选择器用的 SVG（品牌色图形，透明背景，128x128）
  图标来源（许可均允许内嵌再分发）：
    - simple-icons (CC0):        ..\其他库\simple-icons  (github.com/simple-icons/simple-icons)
    - lawnicons   (Apache-2.0):  ..\其他库\lawnicons     (github.com/LawnchairLauncher/lawnicons)
  输出: entry/src/main/resources/rawfile/brand_icons/*.svg
  用法:
    pwsh scripts/download-brand-icons.ps1            # 生成全部
    pwsh scripts/download-brand-icons.ps1 -Find 微信 # 按关键词在两个图标库中查找
#>
param([string]$Find = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$libRoot = Split-Path -Parent $root
$siDir = Join-Path $libRoot '其他库\simple-icons'
$lawnDir = Join-Path $libRoot '其他库\lawnicons'
$outDir = Join-Path $root 'entry/src/main/resources/rawfile/brand_icons'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not (Test-Path (Join-Path $siDir 'data\simple-icons.json'))) { throw "simple-icons 不存在: $siDir" }
if (-not (Test-Path (Join-Path $lawnDir 'app\assets\appfilter.xml'))) { throw "lawnicons 不存在: $lawnDir" }

# ---------------- 清单: file=输出文件名 group=分组 label=显示名 kw=搜索关键词 ----------------
# si=SI slug(优先，颜色取官方 hex) pkg=安卓包名(lawnicons 查找) pref=首选 drawable hex=lawn 来源品牌色
$manifest = @(
  # ---- 国内常用 ----
  [pscustomobject]@{ file='wechat'; group='domestic'; label='微信'; kw='wechat weixin'; si='wechat'; pkg='com.tencent.mm'; pref='wechat'; hex='#07C160' }
  [pscustomobject]@{ file='alipay'; group='domestic'; label='支付宝'; kw='alipay zhifubao'; si='alipay'; pkg='com.eg.android.AlipayGphone'; pref='alipay'; hex='#1677FF' }
  [pscustomobject]@{ file='qq'; group='domestic'; label='QQ'; kw='qq tencent'; si='qq'; pkg='com.tencent.mobileqq'; pref='qq'; hex='#12B7F5' }
  [pscustomobject]@{ file='taobao'; group='domestic'; label='淘宝'; kw='taobao'; si='taobao'; pkg='com.taobao.taobao'; pref='taobao'; hex='#FF5000' }
  [pscustomobject]@{ file='jd'; group='domestic'; label='京东'; kw='jd jingdong'; si=''; pkg='com.jingdong.app.mall'; pref='jd'; hex='#E1251B' }
  [pscustomobject]@{ file='douyin'; group='domestic'; label='抖音'; kw='douyin'; si='tiktok'; pkg='com.ss.android.ugc.aweme'; pref='tiktok'; hex='#FE2C55'; force=$true }
  [pscustomobject]@{ file='xiaohongshu'; group='domestic'; label='小红书'; kw='xiaohongshu xhs rednote'; si='xiaohongshu'; pkg='com.xingin.xhs'; pref='xiaohongshu'; hex='#FF2442' }
  [pscustomobject]@{ file='weibo'; group='domestic'; label='微博'; kw='weibo'; si='sinaweibo'; pkg='com.sina.weibo'; pref='weibo'; hex='#E6162D' }
  [pscustomobject]@{ file='zhihu'; group='domestic'; label='知乎'; kw='zhihu'; si='zhihu'; pkg='com.zhihu.android'; pref='zhihu'; hex='#0084FF' }
  [pscustomobject]@{ file='bilibili'; group='domestic'; label='哔哩哔哩'; kw='bilibili bili'; si='bilibili'; pkg='tv.danmaku.bili'; pref='bilibili'; hex='#00A1D6' }
  [pscustomobject]@{ file='dingtalk'; group='domestic'; label='钉钉'; kw='dingtalk'; si=''; pkg='com.alibaba.android.rimet'; pref='dingtalk'; hex='#0089FF' }
  [pscustomobject]@{ file='feishu'; group='domestic'; label='飞书'; kw='feishu lark'; si=''; pkg='com.ss.android.lark'; pref='feishu'; hex='#3370FF' }
  [pscustomobject]@{ file='meituan'; group='domestic'; label='美团'; kw='meituan'; si=''; pkg='com.sankuai.meituan'; pref='meituan'; hex='#FFC300' }
  [pscustomobject]@{ file='dianping'; group='domestic'; label='大众点评'; kw='dianping'; si=''; pkg='com.dianping.v1'; pref='dianping'; hex='#FF6633' }
  [pscustomobject]@{ file='eleme'; group='domestic'; label='饿了么'; kw='eleme taobao flash'; si=''; pkg='me.ele'; pref='taobao_flash_shopping'; hex='#0085FF' }
  [pscustomobject]@{ file='pinduoduo'; group='domestic'; label='拼多多'; kw='pinduoduo pdd'; si=''; pkg='com.xunmeng.pinduoduo'; pref='pinduoduo'; hex='#E02E24' }
  [pscustomobject]@{ file='xianyu'; group='domestic'; label='闲鱼'; kw='xianyu'; si=''; pkg='com.taobao.idlefish'; pref='idle_fish'; hex='#FFD500' }
  [pscustomobject]@{ file='baidu'; group='domestic'; label='百度'; kw='baidu'; si='baidu'; pkg='com.baidu.searchbox'; pref='baidu'; hex='#2932E1' }
  [pscustomobject]@{ file='baidu_netdisk'; group='domestic'; label='百度网盘'; kw='baidu netdisk wangpan'; si=''; pkg='com.baidu.netdisk'; pref='baidu_netdisk'; hex='#06A8FF' }
  [pscustomobject]@{ file='uc_browser'; group='domestic'; label='UC浏览器'; kw='uc browser liulanqi'; si=''; pkg='com.UCMobile'; pref='uc_browser'; hex='#FF6A00' }
  [pscustomobject]@{ file='quark'; group='domestic'; label='夸克'; kw='quark'; si=''; pkg='com.quark.browser'; pref='quark'; hex='#4C6BFF' }
  [pscustomobject]@{ file='netease_cloud_music'; group='domestic'; label='网易云音乐'; kw='netease cloudmusic yunyinyue'; si='neteasecloudmusic'; pkg='com.netease.cloudmusic'; pref='netease_music'; hex='#C20C0C' }
  [pscustomobject]@{ file='qq_music'; group='domestic'; label='QQ音乐'; kw='qqmusic'; si=''; pkg='com.tencent.qqmusic'; pref='qqmusic'; hex='#31C27C' }
  [pscustomobject]@{ file='kugou_music'; group='domestic'; label='酷狗音乐'; kw='kugou'; si=''; pkg='com.kugou.android'; pref='kugou'; hex='#169AF3' }
  [pscustomobject]@{ file='iqiyi'; group='domestic'; label='爱奇艺'; kw='iqiyi'; si=''; pkg='com.qiyi.video'; pref='iqiyi'; hex='#00BE06' }
  [pscustomobject]@{ file='youku'; group='domestic'; label='优酷'; kw='youku'; si=''; pkg='com.youku.phone'; pref='youku'; hex='#1E9BE8' }
  [pscustomobject]@{ file='tencent_video'; group='domestic'; label='腾讯视频'; kw='tencentvideo video'; si=''; pkg='com.tencent.qqlive'; pref='tencent_video'; hex='#FF6022' }
  [pscustomobject]@{ file='douban'; group='domestic'; label='豆瓣'; kw='douban'; si=''; pkg='com.douban.frodo'; pref='douban'; hex='#007722' }
  [pscustomobject]@{ file='ctrip'; group='domestic'; label='携程旅行'; kw='ctrip xiecheng'; si=''; pkg='ctrip.android.view'; pref='ctrip'; hex='#0086F6' }
  [pscustomobject]@{ file='railway_12306'; group='domestic'; label='铁路12306'; kw='12306 railway huoche'; si=''; pkg='com.MobileTicket'; pref='railway_12306'; hex='#3B99FC' }
  [pscustomobject]@{ file='amap'; group='domestic'; label='高德地图'; kw='amap gaode map ditu'; si=''; pkg='com.autonavi.minimap'; pref='amap'; hex='#0091FF' }
  [pscustomobject]@{ file='didi'; group='domestic'; label='滴滴出行'; kw='didi chuxing'; si=''; pkg='com.sdu.didi.psnger'; pref='didi'; hex='#FF7E33' }
  [pscustomobject]@{ file='hellobike'; group='domestic'; label='哈啰'; kw='hellobike halo'; si=''; pkg='com.jingyao.easybike'; pref='hello'; hex='#00BFAB' }
  [pscustomobject]@{ file='icbc'; group='domestic'; label='中国工商银行'; kw='icbc gongshang bank yinhang'; si=''; pkg='com.icbc'; pref='icbc'; hex='#C7000B' }
  [pscustomobject]@{ file='ccb'; group='domestic'; label='中国建设银行'; kw='ccb jianshe bank yinhang'; si=''; pkg='com.chinamworld.main'; pref='china_construction_bank'; hex='#0066B3' }
  [pscustomobject]@{ file='boc'; group='domestic'; label='中国银行'; kw='boc zhongguo bank yinhang'; si=''; pkg='com.chinamworld.bocmbci'; pref='bank_of_china'; hex='#B02A30' }
  [pscustomobject]@{ file='abc_bank'; group='domestic'; label='中国农业银行'; kw='abc nongye bank yinhang'; si=''; pkg='com.android.bankabc'; pref='agricultural_bank_of_china'; hex='#00923F' }
  [pscustomobject]@{ file='cmb'; group='domestic'; label='招商银行'; kw='cmb zhaoshang bank yinhang'; si=''; pkg='cmb.pb'; pref='china_merchants_bank'; hex='#D22630' }
  [pscustomobject]@{ file='unionpay'; group='domestic'; label='中国银联'; kw='unionpay yinlian'; si=''; pkg='com.unionpay'; pref='unionpay'; hex='#0B4EA2' }
  [pscustomobject]@{ file='wps_office'; group='domestic'; label='WPS Office'; kw='wps office'; si=''; pkg='cn.wps.moffice_eng'; pref='wps_office'; hex='#E8362D' }
  [pscustomobject]@{ file='xunlei'; group='domestic'; label='迅雷'; kw='xunlei thunder'; si=''; pkg='com.xunlei.downloadprovider'; pref='lixian_xunlei'; hex='#3079ED' }
  [pscustomobject]@{ file='coolapk'; group='domestic'; label='酷安'; kw='coolapk'; si=''; pkg='com.coolapk.market'; pref='coolapk'; hex='#009688' }
  [pscustomobject]@{ file='wecom'; group='domestic'; label='企业微信'; kw='wecom qiye wechat work'; si=''; pkg='com.tencent.wework'; pref='wecom'; hex='#0082E9' }
  [pscustomobject]@{ file='kuaishou'; group='domestic'; label='快手'; kw='kuaishou kwai'; si=''; pkg='com.smile.gifmaker'; pref='kwai'; hex='#FF4906' }
  [pscustomobject]@{ file='baidu_tieba'; group='domestic'; label='百度贴吧'; kw='tieba baidu'; si=''; pkg='com.baidu.tieba'; pref='baidu_tieba'; hex='#4E6EF2' }
  [pscustomobject]@{ file='baidu_map'; group='domestic'; label='百度地图'; kw='baidu map ditu'; si=''; pkg='com.baidu.BaiduMap'; pref='baidu_maps'; hex='#3385FF' }
  [pscustomobject]@{ file='qq_mail'; group='domestic'; label='QQ邮箱'; kw='qqmail mail youxiang'; si=''; pkg='com.tencent.androidqqmail'; pref='qqmail'; hex='#12B7F5' }
  [pscustomobject]@{ file='alibaba_1688'; group='domestic'; label='1688'; kw='1688 alibaba'; si=''; pkg='com.alibaba.wireless'; pref='alibaba_1688'; hex='#FF6A00' }
  [pscustomobject]@{ file='aliyundrive'; group='domestic'; label='阿里云盘'; kw='aliyundrive alipan yunpan'; si=''; pkg='com.alicloud.databox'; pref='aliyundrive'; hex='#4C84FF' }
  [pscustomobject]@{ file='umetrip'; group='domestic'; label='航旅纵横'; kw='umetrip hanglv'; si=''; pkg='com.umetrip.android.msky.app'; pref='umetrip'; hex='#2A6AE9' }
  [pscustomobject]@{ file='wifi_master'; group='domestic'; label='WiFi万能钥匙'; kw='wifi key wifimaster'; si=''; pkg='com.snda.wifilocating'; pref='wifi_master'; hex='#00A0E9' }
  [pscustomobject]@{ file='smzdm'; group='domestic'; label='什么值得买'; kw='smzdm zhide'; si=''; pkg='com.smzdm.client.android'; pref='what_to_buy'; hex='#E8262C' }
  [pscustomobject]@{ file='mafengwo'; group='domestic'; label='马蜂窝'; kw='mafengwo travel'; si=''; pkg='com.mfw.roadbook'; pref='hornets_nest'; hex='#FF9D00' }
  [pscustomobject]@{ file='china_mobile'; group='domestic'; label='中国移动'; kw='china mobile yidong 10086'; si=''; pkg='com.greenpoint.android.mc10086.activity'; pref='china_mobile'; hex='#0085D0' }
  [pscustomobject]@{ file='china_unicom'; group='domestic'; label='中国联通'; kw='china unicom liantong 10010'; si=''; pkg='com.sinovatech.unicom.ui'; pref='china_unicom'; hex='#E60012' }
  [pscustomobject]@{ file='china_telecom'; group='domestic'; label='中国电信'; kw='china telecom dianxin 10000'; si=''; pkg='com.ct.client'; pref='china_telecom'; hex='#0066B3' }
  [pscustomobject]@{ file='weread'; group='domestic'; label='微信读书'; kw='weread weixin dushu reading'; si=''; pkg='com.tencent.weread'; pref=''; hex='#2CAE96' }
  [pscustomobject]@{ file='dragon_read'; group='domestic'; label='番茄小说'; kw='fanqie tomato dragonread novel'; si=''; pkg='com.dragon.read'; pref=''; hex='#FF6B2B' }
  [pscustomobject]@{ file='fliggy'; group='domestic'; label='飞猪'; kw='fliggy feizhu travel'; si=''; pkg='com.taobao.trip'; pref=''; hex='#FF7D00' }
  [pscustomobject]@{ file='cainiao'; group='domestic'; label='菜鸟'; kw='cainiao kuaidi delivery'; si=''; pkg='com.cainiao.wireless'; pref=''; hex='#1678FF' }
  [pscustomobject]@{ file='chaoxing'; group='domestic'; label='学习通'; kw='chaoxing xuexitong study'; si=''; pkg='com.chaoxing.mobile'; pref=''; hex='#1E88E5' }
  [pscustomobject]@{ file='honor_of_kings'; group='domestic'; label='王者荣耀'; kw='honorofkings wangzhe sgame'; si=''; pkg='com.tencent.tmgp.sgame'; pref=''; hex='#C9A063' }
  [pscustomobject]@{ file='genshin_impact'; group='domestic'; label='原神'; kw='genshin yuanshen impact'; si=''; pkg='com.miHoYo.Yuanshen'; pref='genshin_impact'; hex='#D3BC8E' }
  [pscustomobject]@{ file='hoyolab'; group='domestic'; label='米游社'; kw='hoyolab miyoushe mihoyo'; si=''; pkg='com.mihoyo.hoyolab'; pref=''; hex='#3B6DF2' }
  [pscustomobject]@{ file='luckin_coffee'; group='domestic'; label='瑞幸咖啡'; kw='luckin coffee ruixing'; si=''; pkg='com.lucky.luckyclient'; pref=''; hex='#1E3F9E' }
  [pscustomobject]@{ file='meituan_takeaway'; group='domestic'; label='美团外卖'; kw='meituan waimai takeaway'; si=''; pkg='com.sankuai.meituan.takeoutnew'; pref=''; hex='#FFC300' }
  [pscustomobject]@{ file='mi_store'; group='domestic'; label='小米商城'; kw='mishop xiaomi store shangcheng'; si=''; pkg='com.xiaomi.shop'; pref=''; hex='#FF6900' }
  [pscustomobject]@{ file='huawei_health'; group='domestic'; label='华为运动健康'; kw='huawei health yundong jiankang'; si=''; pkg='com.huawei.health'; pref=''; hex='#00A29A' }
  [pscustomobject]@{ file='sunlogin'; group='domestic'; label='向日葵远程控制'; kw='sunlogin xiangrikui remote oray'; si=''; pkg='com.oray.sunlogin'; pref=''; hex='#FFAA00' }
  [pscustomobject]@{ file='boss_recruitment'; group='domestic'; label='BOSS直聘'; kw='boss zhipin recruitment zhaopin'; si=''; pkg='com.hpbr.bosszhipin'; pref=''; hex='#00BFFF' }

  # ---- 国外常用 ----
  [pscustomobject]@{ file='google'; group='international'; label='Google'; kw='google'; si='google'; pkg='com.google.android.googlequicksearchbox'; pref='google'; hex='#4285F4' }
  [pscustomobject]@{ file='apple'; group='international'; label='Apple'; kw='apple iphone ios'; si='apple'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='github'; group='international'; label='GitHub'; kw='github'; si='github'; pkg='com.github.android'; pref='github'; hex='#181717' }
  [pscustomobject]@{ file='gitlab'; group='international'; label='GitLab'; kw='gitlab'; si='gitlab'; pkg=''; pref=''; hex='#FC6D26' }
  [pscustomobject]@{ file='amazon'; group='international'; label='Amazon'; kw='amazon shopping'; si=''; pkg='com.amazon.mShop.android.shopping'; pref='amazon_shopping'; hex='#FF9900' }
  [pscustomobject]@{ file='facebook'; group='international'; label='Facebook'; kw='facebook meta'; si='facebook'; pkg='com.facebook.katana'; pref='facebook'; hex='#1877F2' }
  [pscustomobject]@{ file='instagram'; group='international'; label='Instagram'; kw='instagram'; si='instagram'; pkg='com.instagram.android'; pref='instagram'; hex='#E4405F' }
  [pscustomobject]@{ file='x'; group='international'; label='X'; kw='x twitter'; si='x'; pkg='com.twitter.android'; pref='x'; hex='#000000' }
  [pscustomobject]@{ file='tiktok'; group='international'; label='TikTok'; kw='tiktok'; si='tiktok'; pkg='com.zhiliaoapp.musically'; pref='tiktok'; hex='#000000' }
  [pscustomobject]@{ file='linkedin'; group='international'; label='LinkedIn'; kw='linkedin'; si=''; pkg='com.linkedin.android'; pref='linkedin'; hex='#0A66C2' }
  [pscustomobject]@{ file='youtube'; group='international'; label='YouTube'; kw='youtube'; si='youtube'; pkg='com.google.android.youtube'; pref='youtube'; hex='#FF0000' }
  [pscustomobject]@{ file='netflix'; group='international'; label='Netflix'; kw='netflix'; si='netflix'; pkg='com.netflix.mediaclient'; pref='netflix'; hex='#E50914' }
  [pscustomobject]@{ file='spotify'; group='international'; label='Spotify'; kw='spotify'; si='spotify'; pkg='com.spotify.music'; pref='spotify'; hex='#1DB954' }
  [pscustomobject]@{ file='discord'; group='international'; label='Discord'; kw='discord'; si='discord'; pkg='com.discord'; pref='discord'; hex='#5865F2' }
  [pscustomobject]@{ file='reddit'; group='international'; label='Reddit'; kw='reddit'; si='reddit'; pkg='com.reddit.frontpage'; pref='reddit'; hex='#FF4500' }
  [pscustomobject]@{ file='steam'; group='international'; label='Steam'; kw='steam valve'; si='steam'; pkg='com.valvesoftware.android.steam.community'; pref='steam'; hex='#000000' }
  [pscustomobject]@{ file='twitch'; group='international'; label='Twitch'; kw='twitch'; si='twitch'; pkg='tv.twitch.android.app'; pref='twitch'; hex='#9146FF' }
  [pscustomobject]@{ file='whatsapp'; group='international'; label='WhatsApp'; kw='whatsapp'; si='whatsapp'; pkg='com.whatsapp'; pref='whatsapp'; hex='#25D366' }
  [pscustomobject]@{ file='telegram'; group='international'; label='Telegram'; kw='telegram'; si='telegram'; pkg='org.telegram.messenger'; pref='telegram'; hex='#26A5E4' }
  [pscustomobject]@{ file='signal'; group='international'; label='Signal'; kw='signal'; si='signal'; pkg='org.thoughtcrime.securesms'; pref='signal'; hex='#3A76F0' }
  [pscustomobject]@{ file='slack'; group='international'; label='Slack'; kw='slack'; si=''; pkg='com.Slack'; pref='slack'; hex='#4A154B' }
  [pscustomobject]@{ file='snapchat'; group='international'; label='Snapchat'; kw='snapchat'; si='snapchat'; pkg='com.snapchat.android'; pref='snapchat'; hex='#FFFC00' }
  [pscustomobject]@{ file='pinterest'; group='international'; label='Pinterest'; kw='pinterest'; si='pinterest'; pkg='com.pinterest'; pref='pinterest'; hex='#BD081C' }
  [pscustomobject]@{ file='line'; group='international'; label='LINE'; kw='line'; si='line'; pkg='jp.naver.line.android'; pref='line'; hex='#00C300' }
  [pscustomobject]@{ file='paypal'; group='international'; label='PayPal'; kw='paypal'; si='paypal'; pkg='com.paypal.android.p2pmobile'; pref='paypal'; hex='#00457C' }
  [pscustomobject]@{ file='stripe'; group='international'; label='Stripe'; kw='stripe'; si='stripe'; pkg='com.stripe.android'; pref='stripe'; hex='#635BFF' }
  [pscustomobject]@{ file='visa'; group='international'; label='Visa'; kw='visa'; si='visa'; pkg=''; pref=''; hex='#1A1F71' }
  [pscustomobject]@{ file='mastercard'; group='international'; label='Mastercard'; kw='mastercard'; si='mastercard'; pkg=''; pref=''; hex='#EB001B' }
  [pscustomobject]@{ file='american_express'; group='international'; label='American Express'; kw='amex americanexpress'; si='americanexpress'; pkg=''; pref=''; hex='#2E77BC' }
  [pscustomobject]@{ file='google_drive'; group='international'; label='Google Drive'; kw='googledrive drive'; si='googledrive'; pkg='com.google.android.apps.docs'; pref='google_drive'; hex='#4285F4' }
  [pscustomobject]@{ file='dropbox'; group='international'; label='Dropbox'; kw='dropbox'; si='dropbox'; pkg='com.dropbox.android'; pref='dropbox'; hex='#0061FF' }
  [pscustomobject]@{ file='onedrive'; group='international'; label='OneDrive'; kw='onedrive'; si=''; pkg='com.microsoft.skydrive'; pref='microsoft_onedrive'; hex='#0078D4' }
  [pscustomobject]@{ file='icloud'; group='international'; label='iCloud'; kw='icloud'; si='icloud'; pkg=''; pref=''; hex='#3693F3' }
  [pscustomobject]@{ file='notion'; group='international'; label='Notion'; kw='notion'; si='notion'; pkg='notion.id'; pref='notion'; hex='#000000' }
  [pscustomobject]@{ file='openai'; group='international'; label='OpenAI'; kw='openai chatgpt'; si=''; pkg='com.openai.chatgpt'; pref='chatgpt'; hex='#412991' }
  [pscustomobject]@{ file='bitwarden'; group='international'; label='Bitwarden'; kw='bitwarden'; si='bitwarden'; pkg='com.x8bit.bitwarden'; pref='bitwarden'; hex='#175DDC' }
  [pscustomobject]@{ file='onepassword'; group='international'; label='1Password'; kw='1password'; si='1password'; pkg='com.agilebits.onepassword'; pref='_1password'; hex='#1A8CFF' }
  [pscustomobject]@{ file='lastpass'; group='international'; label='LastPass'; kw='lastpass'; si='lastpass'; pkg='com.lastpass.lpandroid'; pref='lastpass'; hex='#D32D27' }
  [pscustomobject]@{ file='cloudflare'; group='international'; label='Cloudflare'; kw='cloudflare'; si='cloudflare'; pkg=''; pref=''; hex='#F38020' }
  [pscustomobject]@{ file='firefox'; group='international'; label='Firefox'; kw='firefox browser'; si='firefoxbrowser'; pkg='org.mozilla.firefox'; pref='firefox'; hex='#FF7139' }
  [pscustomobject]@{ file='chrome'; group='international'; label='Chrome'; kw='chrome browser'; si='googlechrome'; pkg='com.android.chrome'; pref='google_chrome'; hex='#4285F4' }
  [pscustomobject]@{ file='safari'; group='international'; label='Safari'; kw='safari browser'; si='safari'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='linux'; group='international'; label='Linux'; kw='linux'; si='linux'; pkg=''; pref=''; hex='#FCC624' }
  [pscustomobject]@{ file='ubuntu'; group='international'; label='Ubuntu'; kw='ubuntu'; si='ubuntu'; pkg=''; pref=''; hex='#E95420' }
  [pscustomobject]@{ file='docker'; group='international'; label='Docker'; kw='docker'; si='docker'; pkg=''; pref=''; hex='#2496ED' }
  [pscustomobject]@{ file='kubernetes'; group='international'; label='Kubernetes'; kw='kubernetes k8s'; si='kubernetes'; pkg=''; pref=''; hex='#326CE5' }
  [pscustomobject]@{ file='nintendo'; group='international'; label='Nintendo Switch'; kw='nintendo switch'; si=''; pkg='com.nintendo.znca'; pref='nintendo_switch'; hex='#E60012' }
  [pscustomobject]@{ file='playstation'; group='international'; label='PlayStation'; kw='playstation sony ps5'; si='playstation'; pkg='com.scee.psxandroid'; pref='playstation_ps'; hex='#003791' }
  [pscustomobject]@{ file='xbox'; group='international'; label='Xbox'; kw='xbox'; si=''; pkg='com.microsoft.xboxone.smartglass'; pref='xbox'; hex='#107C10' }
  [pscustomobject]@{ file='epic_games'; group='international'; label='Epic Games'; kw='epicgames'; si='epicgames'; pkg=''; pref=''; hex='#313131' }
  [pscustomobject]@{ file='minecraft'; group='international'; label='Minecraft'; kw='minecraft'; si=''; pkg='com.mojang.minecraftpe'; pref='minecraft'; hex='#62B47A' }
  [pscustomobject]@{ file='roblox'; group='international'; label='Roblox'; kw='roblox'; si='roblox'; pkg='com.roblox.client'; pref='roblox'; hex='#000000' }
  [pscustomobject]@{ file='riot_games'; group='international'; label='Riot Games'; kw='riotgames leagueoflegends'; si='riotgames'; pkg=''; pref=''; hex='#D32936' }
  [pscustomobject]@{ file='gitee'; group='international'; label='Gitee'; kw='gitee'; si='gitee'; pkg=''; pref=''; hex='#C71D23' }
  [pscustomobject]@{ file='proton_vpn'; group='international'; label='Proton VPN'; kw='protonvpn vpn'; si='protonvpn'; pkg=''; pref=''; hex='#6D4AFF' }
  [pscustomobject]@{ file='proton_mail'; group='international'; label='Proton Mail'; kw='protonmail mail'; si='protonmail'; pkg=''; pref=''; hex='#6D4AFF' }
  [pscustomobject]@{ file='keepassxc'; group='international'; label='KeePassXC'; kw='keepassxc keepass'; si='keepassxc'; pkg=''; pref=''; hex='#6CAC4D' }
  [pscustomobject]@{ file='stackoverflow'; group='international'; label='Stack Overflow'; kw='stackoverflow'; si='stackoverflow'; pkg=''; pref=''; hex='#F58025' }
  [pscustomobject]@{ file='hackerrank'; group='international'; label='HackerRank'; kw='hackerrank'; si='hackerrank'; pkg=''; pref=''; hex='#00EA64' }
  [pscustomobject]@{ file='leetcode'; group='international'; label='LeetCode'; kw='leetcode'; si='leetcode'; pkg=''; pref=''; hex='#FFA116' }
  [pscustomobject]@{ file='freecodecamp'; group='international'; label='freeCodeCamp'; kw='freecodecamp fcc'; si='freecodecamp'; pkg=''; pref=''; hex='#0A0A0A' }
  [pscustomobject]@{ file='bitcoin'; group='international'; label='Bitcoin'; kw='bitcoin btc crypto'; si='bitcoin'; pkg=''; pref=''; hex='#F7931A' }
  [pscustomobject]@{ file='ethereum'; group='international'; label='Ethereum'; kw='ethereum eth crypto'; si='ethereum'; pkg=''; pref=''; hex='#3C3C3D' }
  [pscustomobject]@{ file='coinbase'; group='international'; label='Coinbase'; kw='coinbase crypto'; si='coinbase'; pkg=''; pref=''; hex='#0052FF' }
  [pscustomobject]@{ file='binance'; group='international'; label='Binance'; kw='binance crypto'; si='binance'; pkg=''; pref=''; hex='#F0B90B' }
  [pscustomobject]@{ file='brave'; group='international'; label='Brave'; kw='brave browser'; si='brave'; pkg=''; pref=''; hex='#FB542B' }
  [pscustomobject]@{ file='opera'; group='international'; label='Opera'; kw='opera browser'; si='opera'; pkg=''; pref=''; hex='#FF1B2D' }
  [pscustomobject]@{ file='airbnb'; group='international'; label='Airbnb'; kw='airbnb'; si='airbnb'; pkg=''; pref=''; hex='#FF5A5F' }
  [pscustomobject]@{ file='uber'; group='international'; label='Uber'; kw='uber'; si='uber'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='booking'; group='international'; label='Booking.com'; kw='booking travel'; si='bookingdotcom'; pkg=''; pref=''; hex='#003580' }
  [pscustomobject]@{ file='ebay'; group='international'; label='eBay'; kw='ebay shopping'; si='ebay'; pkg=''; pref=''; hex='#E53238' }
  [pscustomobject]@{ file='shopify'; group='international'; label='Shopify'; kw='shopify'; si='shopify'; pkg=''; pref=''; hex='#7AB55C' }
  [pscustomobject]@{ file='etsy'; group='international'; label='Etsy'; kw='etsy'; si='etsy'; pkg=''; pref=''; hex='#F1641E' }
  [pscustomobject]@{ file='duolingo'; group='international'; label='Duolingo'; kw='duolingo'; si='duolingo'; pkg=''; pref=''; hex='#58CC02' }
  [pscustomobject]@{ file='coursera'; group='international'; label='Coursera'; kw='coursera'; si='coursera'; pkg=''; pref=''; hex='#0056D2' }
  [pscustomobject]@{ file='udemy'; group='international'; label='Udemy'; kw='udemy'; si='udemy'; pkg=''; pref=''; hex='#A435F0' }
  [pscustomobject]@{ file='khan_academy'; group='international'; label='Khan Academy'; kw='khanacademy'; si='khanacademy'; pkg=''; pref=''; hex='#14BF96' }
  [pscustomobject]@{ file='soundcloud'; group='international'; label='SoundCloud'; kw='soundcloud'; si='soundcloud'; pkg=''; pref=''; hex='#FF5500' }
  [pscustomobject]@{ file='apple_music'; group='international'; label='Apple Music'; kw='applemusic music'; si='applemusic'; pkg=''; pref=''; hex='#FA243C' }
  [pscustomobject]@{ file='vimeo'; group='international'; label='Vimeo'; kw='vimeo'; si='vimeo'; pkg=''; pref=''; hex='#1AB7EA' }
  [pscustomobject]@{ file='threads'; group='international'; label='Threads'; kw='threads'; si='threads'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='mastodon'; group='international'; label='Mastodon'; kw='mastodon'; si='mastodon'; pkg=''; pref=''; hex='#6364FF' }
  [pscustomobject]@{ file='bluesky'; group='international'; label='Bluesky'; kw='bluesky bsky'; si='bluesky'; pkg=''; pref=''; hex='#0285FF' }
  [pscustomobject]@{ file='tumblr'; group='international'; label='Tumblr'; kw='tumblr'; si='tumblr'; pkg=''; pref=''; hex='#36465D' }
  [pscustomobject]@{ file='medium'; group='international'; label='Medium'; kw='medium'; si='medium'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='wordpress'; group='international'; label='WordPress'; kw='wordpress'; si='wordpress'; pkg=''; pref=''; hex='#21759B' }
  [pscustomobject]@{ file='figma'; group='international'; label='Figma'; kw='figma design'; si='figma'; pkg=''; pref=''; hex='#F24E1E' }
  [pscustomobject]@{ file='todoist'; group='international'; label='Todoist'; kw='todoist'; si='todoist'; pkg=''; pref=''; hex='#E44332' }
  [pscustomobject]@{ file='evernote'; group='international'; label='Evernote'; kw='evernote'; si='evernote'; pkg=''; pref=''; hex='#00A82D' }
  [pscustomobject]@{ file='teamviewer'; group='international'; label='TeamViewer'; kw='teamviewer'; si='teamviewer'; pkg=''; pref=''; hex='#0E8EE9' }
  [pscustomobject]@{ file='google_meet'; group='international'; label='Google Meet'; kw='googlemeet meet'; si='googlemeet'; pkg=''; pref=''; hex='#00832D' }
  [pscustomobject]@{ file='gmail'; group='international'; label='Gmail'; kw='gmail mail'; si='gmail'; pkg=''; pref=''; hex='#EA4335' }
  [pscustomobject]@{ file='google_maps'; group='international'; label='Google Maps'; kw='googlemaps map'; si='googlemaps'; pkg=''; pref=''; hex='#4285F4' }
  [pscustomobject]@{ file='google_photos'; group='international'; label='Google Photos'; kw='googlephotos photo'; si='googlephotos'; pkg=''; pref=''; hex='#4285F4' }
  [pscustomobject]@{ file='google_calendar'; group='international'; label='Google Calendar'; kw='googlecalendar calendar'; si='googlecalendar'; pkg=''; pref=''; hex='#4285F4' }
  [pscustomobject]@{ file='youtube_music'; group='international'; label='YouTube Music'; kw='youtubemusic music'; si='youtubemusic'; pkg=''; pref=''; hex='#FF0000' }
  [pscustomobject]@{ file='nextcloud'; group='international'; label='Nextcloud'; kw='nextcloud'; si='nextcloud'; pkg=''; pref=''; hex='#0082C9' }
  [pscustomobject]@{ file='jellyfin'; group='international'; label='Jellyfin'; kw='jellyfin'; si='jellyfin'; pkg=''; pref=''; hex='#00A4DC' }
  [pscustomobject]@{ file='home_assistant'; group='international'; label='Home Assistant'; kw='homeassistant hass'; si='homeassistant'; pkg=''; pref=''; hex='#41BDF5' }
  [pscustomobject]@{ file='grafana'; group='international'; label='Grafana'; kw='grafana'; si='grafana'; pkg=''; pref=''; hex='#F46800' }
  [pscustomobject]@{ file='git'; group='international'; label='Git'; kw='git'; si='git'; pkg=''; pref=''; hex='#F05032' }
  [pscustomobject]@{ file='python'; group='international'; label='Python'; kw='python'; si='python'; pkg=''; pref=''; hex='#3776AB' }
  [pscustomobject]@{ file='nodejs'; group='international'; label='Node.js'; kw='nodejs node'; si='nodedotjs'; pkg=''; pref=''; hex='#5FA04E' }
  [pscustomobject]@{ file='rust'; group='international'; label='Rust'; kw='rust'; si='rust'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='go'; group='international'; label='Go'; kw='go golang'; si='go'; pkg=''; pref=''; hex='#00ADD8' }
  [pscustomobject]@{ file='alibaba_cloud'; group='international'; label='Alibaba Cloud'; kw='alibabacloud alicloud'; si='alibabacloud'; pkg=''; pref=''; hex='#FF6A00' }
  [pscustomobject]@{ file='vercel'; group='international'; label='Vercel'; kw='vercel'; si='vercel'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='netlify'; group='international'; label='Netlify'; kw='netlify'; si='netlify'; pkg=''; pref=''; hex='#00C7B7' }
  [pscustomobject]@{ file='adguard'; group='international'; label='AdGuard'; kw='adguard'; si='adguard'; pkg=''; pref=''; hex='#68BC71' }
  [pscustomobject]@{ file='wise'; group='international'; label='Wise'; kw='wise transferwise'; si='wise'; pkg=''; pref=''; hex='#9FE870' }
  [pscustomobject]@{ file='revolut'; group='international'; label='Revolut'; kw='revolut'; si='revolut'; pkg=''; pref=''; hex='#191C1F' }
  [pscustomobject]@{ file='kakaotalk'; group='international'; label='KakaoTalk'; kw='kakaotalk kakao'; si='kakaotalk'; pkg=''; pref=''; hex='#FFCD00' }
  [pscustomobject]@{ file='naver'; group='international'; label='Naver'; kw='naver'; si='naver'; pkg=''; pref=''; hex='#03C75A' }
  [pscustomobject]@{ file='viber'; group='international'; label='Viber'; kw='viber'; si='viber'; pkg=''; pref=''; hex='#7360F2' }
  [pscustomobject]@{ file='grab'; group='international'; label='Grab'; kw='grab'; si='grab'; pkg=''; pref=''; hex='#00B14F' }
  [pscustomobject]@{ file='gojek'; group='international'; label='Gojek'; kw='gojek'; si='gojek'; pkg=''; pref=''; hex='#00AA13' }
  [pscustomobject]@{ file='shopee'; group='international'; label='Shopee'; kw='shopee'; si='shopee'; pkg=''; pref=''; hex='#EE4D2D' }
  [pscustomobject]@{ file='rakuten'; group='international'; label='Rakuten'; kw='rakuten'; si='rakuten'; pkg=''; pref=''; hex='#BF0000' }
  [pscustomobject]@{ file='tinder'; group='international'; label='Tinder'; kw='tinder'; si='tinder'; pkg=''; pref=''; hex='#FF6B6B' }
  [pscustomobject]@{ file='substack'; group='international'; label='Substack'; kw='substack'; si='substack'; pkg=''; pref=''; hex='#FF6719' }
  [pscustomobject]@{ file='patreon'; group='international'; label='Patreon'; kw='patreon'; si='patreon'; pkg=''; pref=''; hex='#FF424D' }
  [pscustomobject]@{ file='starbucks'; group='international'; label='Starbucks'; kw='starbucks coffee'; si='starbucks'; pkg=''; pref=''; hex='#00704A' }
  [pscustomobject]@{ file='mcdonalds'; group='international'; label="McDonald's"; kw='mcdonalds'; si='mcdonalds'; pkg=''; pref=''; hex='#FBC817' }
  [pscustomobject]@{ file='kfc'; group='international'; label='KFC'; kw='kfc'; si='kfc'; pkg=''; pref=''; hex='#F40027' }
  [pscustomobject]@{ file='burgerking'; group='international'; label='Burger King'; kw='burgerking'; si='burgerking'; pkg=''; pref=''; hex='#DD1A34' }
  [pscustomobject]@{ file='tacobell'; group='international'; label='Taco Bell'; kw='tacobell'; si='tacobell'; pkg=''; pref=''; hex='#38052C' }
  [pscustomobject]@{ file='ikea'; group='international'; label='IKEA'; kw='ikea'; si='ikea'; pkg=''; pref=''; hex='#0058A3' }
  [pscustomobject]@{ file='target'; group='international'; label='Target'; kw='target'; si='target'; pkg=''; pref=''; hex='#CC0000' }
  [pscustomobject]@{ file='aliexpress'; group='international'; label='AliExpress'; kw='aliexpress'; si='aliexpress'; pkg=''; pref=''; hex='#FF4747' }
  [pscustomobject]@{ file='ubereats'; group='international'; label='Uber Eats'; kw='ubereats'; si='ubereats'; pkg=''; pref=''; hex='#06C167' }
  [pscustomobject]@{ file='doordash'; group='international'; label='DoorDash'; kw='doordash'; si='doordash'; pkg=''; pref=''; hex='#FF3008' }
  [pscustomobject]@{ file='deliveroo'; group='international'; label='Deliveroo'; kw='deliveroo'; si='deliveroo'; pkg=''; pref=''; hex='#00CCBC' }
  [pscustomobject]@{ file='lyft'; group='international'; label='Lyft'; kw='lyft'; si='lyft'; pkg=''; pref=''; hex='#FF00BF' }
  [pscustomobject]@{ file='expedia'; group='international'; label='Expedia'; kw='expedia travel'; si='expedia'; pkg=''; pref=''; hex='#191E3B' }
  [pscustomobject]@{ file='tripadvisor'; group='international'; label='Tripadvisor'; kw='tripadvisor travel'; si='tripadvisor'; pkg=''; pref=''; hex='#34E0A1' }
  [pscustomobject]@{ file='lufthansa'; group='international'; label='Lufthansa'; kw='lufthansa airline'; si='lufthansa'; pkg=''; pref=''; hex='#05164D' }
  [pscustomobject]@{ file='emirates'; group='international'; label='Emirates'; kw='emirates airline'; si='emirates'; pkg=''; pref=''; hex='#D71921' }
  [pscustomobject]@{ file='britishairways'; group='international'; label='British Airways'; kw='britishairways airline'; si='britishairways'; pkg=''; pref=''; hex='#075AAA' }
  [pscustomobject]@{ file='qantas'; group='international'; label='Qantas'; kw='qantas airline'; si='qantas'; pkg=''; pref=''; hex='#E40000' }
  [pscustomobject]@{ file='ryanair'; group='international'; label='Ryanair'; kw='ryanair airline'; si='ryanair'; pkg=''; pref=''; hex='#073590' }
  [pscustomobject]@{ file='hbo'; group='international'; label='HBO'; kw='hbo'; si='hbo'; pkg=''; pref=''; hex='#991EEB' }
  [pscustomobject]@{ file='appletv'; group='international'; label='Apple TV'; kw='appletv'; si='appletv'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='crunchyroll'; group='international'; label='Crunchyroll'; kw='crunchyroll anime'; si='crunchyroll'; pkg=''; pref=''; hex='#F47521' }
  [pscustomobject]@{ file='tidal'; group='international'; label='TIDAL'; kw='tidal music'; si='tidal'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='deezer'; group='international'; label='Deezer'; kw='deezer music'; si='deezer'; pkg=''; pref=''; hex='#A238FF' }
  [pscustomobject]@{ file='pandora'; group='international'; label='Pandora'; kw='pandora music'; si='pandora'; pkg=''; pref=''; hex='#3668FF' }
  [pscustomobject]@{ file='bandcamp'; group='international'; label='Bandcamp'; kw='bandcamp music'; si='bandcamp'; pkg=''; pref=''; hex='#629AA9' }
  [pscustomobject]@{ file='shazam'; group='international'; label='Shazam'; kw='shazam music'; si='shazam'; pkg=''; pref=''; hex='#0088FF' }
  [pscustomobject]@{ file='audible'; group='international'; label='Audible'; kw='audible book'; si='audible'; pkg=''; pref=''; hex='#F8991C' }
  [pscustomobject]@{ file='goodreads'; group='international'; label='Goodreads'; kw='goodreads book'; si='goodreads'; pkg=''; pref=''; hex='#382110' }
  [pscustomobject]@{ file='archiveofourown'; group='international'; label='AO3'; kw='archiveofourown ao3'; si='archiveofourown'; pkg=''; pref=''; hex='#990000' }
  [pscustomobject]@{ file='myanimelist'; group='international'; label='MyAnimeList'; kw='myanimelist anime mal'; si='myanimelist'; pkg=''; pref=''; hex='#2E51A2' }
  [pscustomobject]@{ file='chessdotcom'; group='international'; label='Chess.com'; kw='chess'; si='chessdotcom'; pkg=''; pref=''; hex='#81B64C' }
  [pscustomobject]@{ file='lichess'; group='international'; label='Lichess'; kw='lichess chess'; si='lichess'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='edx'; group='international'; label='edX'; kw='edx'; si='edx'; pkg=''; pref=''; hex='#02262B' }
  [pscustomobject]@{ file='skillshare'; group='international'; label='Skillshare'; kw='skillshare'; si='skillshare'; pkg=''; pref=''; hex='#00FF84' }
  [pscustomobject]@{ file='pluralsight'; group='international'; label='Pluralsight'; kw='pluralsight'; si='pluralsight'; pkg=''; pref=''; hex='#F15B2A' }
  [pscustomobject]@{ file='codecademy'; group='international'; label='Codecademy'; kw='codecademy'; si='codecademy'; pkg=''; pref=''; hex='#1F4056' }
  [pscustomobject]@{ file='codewars'; group='international'; label='Codewars'; kw='codewars'; si='codewars'; pkg=''; pref=''; hex='#B1361E' }
  [pscustomobject]@{ file='codeforces'; group='international'; label='Codeforces'; kw='codeforces'; si='codeforces'; pkg=''; pref=''; hex='#1F8ACB' }
  [pscustomobject]@{ file='jetbrains'; group='international'; label='JetBrains'; kw='jetbrains'; si='jetbrains'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='sublimetext'; group='international'; label='Sublime Text'; kw='sublimetext'; si='sublimetext'; pkg=''; pref=''; hex='#FF9800' }
  [pscustomobject]@{ file='neovim'; group='international'; label='Neovim'; kw='neovim'; si='neovim'; pkg=''; pref=''; hex='#57A143' }
  [pscustomobject]@{ file='vim'; group='international'; label='Vim'; kw='vim'; si='vim'; pkg=''; pref=''; hex='#019733' }
  [pscustomobject]@{ file='notepadplusplus'; group='international'; label='Notepad++'; kw='notepadplusplus'; si='notepadplusplus'; pkg=''; pref=''; hex='#90E59A' }
  [pscustomobject]@{ file='monzo'; group='international'; label='Monzo'; kw='monzo bank'; si='monzo'; pkg=''; pref=''; hex='#FF4F40' }
  [pscustomobject]@{ file='robinhood'; group='international'; label='Robinhood'; kw='robinhood'; si='robinhood'; pkg=''; pref=''; hex='#00C805' }
  [pscustomobject]@{ file='tradingview'; group='international'; label='TradingView'; kw='tradingview'; si='tradingview'; pkg=''; pref=''; hex='#131722' }
  [pscustomobject]@{ file='imgur'; group='international'; label='Imgur'; kw='imgur'; si='imgur'; pkg=''; pref=''; hex='#1BB76E' }
  [pscustomobject]@{ file='quora'; group='international'; label='Quora'; kw='quora'; si='quora'; pkg=''; pref=''; hex='#B92B27' }
  [pscustomobject]@{ file='vk'; group='international'; label='VK'; kw='vk vkontakte'; si='vk'; pkg=''; pref=''; hex='#0077FF' }
  [pscustomobject]@{ file='nextdoor'; group='international'; label='Nextdoor'; kw='nextdoor'; si='nextdoor'; pkg=''; pref=''; hex='#8ED500' }
  [pscustomobject]@{ file='ecosia'; group='international'; label='Ecosia'; kw='ecosia'; si='ecosia'; pkg=''; pref=''; hex='#008009' }
  [pscustomobject]@{ file='duckduckgo'; group='international'; label='DuckDuckGo'; kw='duckduckgo search'; si='duckduckgo'; pkg=''; pref=''; hex='#DE5833' }
  [pscustomobject]@{ file='huggingface'; group='international'; label='Hugging Face'; kw='huggingface'; si='huggingface'; pkg=''; pref=''; hex='#FFD21E' }
  [pscustomobject]@{ file='plex'; group='international'; label='Plex'; kw='plex'; si='plex'; pkg=''; pref=''; hex='#E5A00D' }
  [pscustomobject]@{ file='emby'; group='international'; label='Emby'; kw='emby'; si='emby'; pkg=''; pref=''; hex='#52B54B' }
  [pscustomobject]@{ file='anydesk'; group='international'; label='AnyDesk'; kw='anydesk remote'; si='anydesk'; pkg=''; pref=''; hex='#EF4444' }
  [pscustomobject]@{ file='dashlane'; group='international'; label='Dashlane'; kw='dashlane'; si='dashlane'; pkg=''; pref=''; hex='#0E353D' }
  [pscustomobject]@{ file='kaspersky'; group='international'; label='Kaspersky'; kw='kaspersky'; si='kaspersky'; pkg=''; pref=''; hex='#009981' }
  [pscustomobject]@{ file='avast'; group='international'; label='Avast'; kw='avast'; si='avast'; pkg=''; pref=''; hex='#FF7800' }
  [pscustomobject]@{ file='bitbucket'; group='international'; label='Bitbucket'; kw='bitbucket'; si='bitbucket'; pkg=''; pref=''; hex='#0052CC' }
  [pscustomobject]@{ file='jira'; group='international'; label='Jira'; kw='jira atlassian'; si='jira'; pkg=''; pref=''; hex='#0052CC' }
  [pscustomobject]@{ file='trello'; group='international'; label='Trello'; kw='trello atlassian'; si='trello'; pkg=''; pref=''; hex='#0079BF' }
  [pscustomobject]@{ file='asana'; group='international'; label='Asana'; kw='asana'; si='asana'; pkg=''; pref=''; hex='#F06A6A' }
  [pscustomobject]@{ file='airtable'; group='international'; label='Airtable'; kw='airtable'; si='airtable'; pkg=''; pref=''; hex='#18BFFF' }
  [pscustomobject]@{ file='jenkins'; group='international'; label='Jenkins'; kw='jenkins ci'; si='jenkins'; pkg=''; pref=''; hex='#D24939' }
  [pscustomobject]@{ file='circleci'; group='international'; label='CircleCI'; kw='circleci ci'; si='circleci'; pkg=''; pref=''; hex='#343434' }
  [pscustomobject]@{ file='terraform'; group='international'; label='Terraform'; kw='terraform'; si='terraform'; pkg=''; pref=''; hex='#7B42BC' }
  [pscustomobject]@{ file='ansible'; group='international'; label='Ansible'; kw='ansible'; si='ansible'; pkg=''; pref=''; hex='#EE0000' }
  [pscustomobject]@{ file='prometheus'; group='international'; label='Prometheus'; kw='prometheus'; si='prometheus'; pkg=''; pref=''; hex='#E6522C' }
  [pscustomobject]@{ file='sentry'; group='international'; label='Sentry'; kw='sentry'; si='sentry'; pkg=''; pref=''; hex='#362D59' }
  [pscustomobject]@{ file='postman'; group='international'; label='Postman'; kw='postman api'; si='postman'; pkg=''; pref=''; hex='#FF6C37' }
  [pscustomobject]@{ file='nginx'; group='international'; label='Nginx'; kw='nginx'; si='nginx'; pkg=''; pref=''; hex='#009639' }
  [pscustomobject]@{ file='postgresql'; group='international'; label='PostgreSQL'; kw='postgresql postgres db'; si='postgresql'; pkg=''; pref=''; hex='#4169E1' }
  [pscustomobject]@{ file='mysql'; group='international'; label='MySQL'; kw='mysql db'; si='mysql'; pkg=''; pref=''; hex='#4479A1' }
  [pscustomobject]@{ file='mongodb'; group='international'; label='MongoDB'; kw='mongodb db'; si='mongodb'; pkg=''; pref=''; hex='#47A248' }
  [pscustomobject]@{ file='redis'; group='international'; label='Redis'; kw='redis db'; si='redis'; pkg=''; pref=''; hex='#DC382D' }
  [pscustomobject]@{ file='sqlite'; group='international'; label='SQLite'; kw='sqlite db'; si='sqlite'; pkg=''; pref=''; hex='#003B57' }
  [pscustomobject]@{ file='elasticsearch'; group='international'; label='Elasticsearch'; kw='elasticsearch elastic'; si='elasticsearch'; pkg=''; pref=''; hex='#00BFB3' }
  [pscustomobject]@{ file='typescript'; group='international'; label='TypeScript'; kw='typescript ts'; si='typescript'; pkg=''; pref=''; hex='#3178C6' }
  [pscustomobject]@{ file='javascript'; group='international'; label='JavaScript'; kw='javascript js'; si='javascript'; pkg=''; pref=''; hex='#F7DF1E' }
  [pscustomobject]@{ file='kotlin'; group='international'; label='Kotlin'; kw='kotlin'; si='kotlin'; pkg=''; pref=''; hex='#7F52FF' }
  [pscustomobject]@{ file='swift'; group='international'; label='Swift'; kw='swift'; si='swift'; pkg=''; pref=''; hex='#F05138' }
  [pscustomobject]@{ file='dart'; group='international'; label='Dart'; kw='dart'; si='dart'; pkg=''; pref=''; hex='#0175C2' }
  [pscustomobject]@{ file='flutter'; group='international'; label='Flutter'; kw='flutter'; si='flutter'; pkg=''; pref=''; hex='#02569B' }
  [pscustomobject]@{ file='react'; group='international'; label='React'; kw='react'; si='react'; pkg=''; pref=''; hex='#61DAFB' }
  [pscustomobject]@{ file='vuedotjs'; group='international'; label='Vue.js'; kw='vue vuejs'; si='vuedotjs'; pkg=''; pref=''; hex='#4FC08D' }
  [pscustomobject]@{ file='angular'; group='international'; label='Angular'; kw='angular'; si='angular'; pkg=''; pref=''; hex='#0F0F11' }
  [pscustomobject]@{ file='svelte'; group='international'; label='Svelte'; kw='svelte'; si='svelte'; pkg=''; pref=''; hex='#FF3E00' }
  [pscustomobject]@{ file='laravel'; group='international'; label='Laravel'; kw='laravel php'; si='laravel'; pkg=''; pref=''; hex='#FF2D20' }
  [pscustomobject]@{ file='django'; group='international'; label='Django'; kw='django python'; si='django'; pkg=''; pref=''; hex='#092E20' }
  [pscustomobject]@{ file='rubyonrails'; group='international'; label='Ruby on Rails'; kw='rubyonrails rails'; si='rubyonrails'; pkg=''; pref=''; hex='#CC0000' }
  [pscustomobject]@{ file='spring'; group='international'; label='Spring'; kw='spring java'; si='spring'; pkg=''; pref=''; hex='#6DB33F' }
  [pscustomobject]@{ file='dotnet'; group='international'; label='.NET'; kw='dotnet net'; si='dotnet'; pkg=''; pref=''; hex='#512BD4' }
  [pscustomobject]@{ file='php'; group='international'; label='PHP'; kw='php'; si='php'; pkg=''; pref=''; hex='#777BB4' }
  [pscustomobject]@{ file='c'; group='international'; label='C'; kw='c clang'; si='c'; pkg=''; pref=''; hex='#A8B9CC' }
  [pscustomobject]@{ file='cplusplus'; group='international'; label='C++'; kw='cplusplus cpp'; si='cplusplus'; pkg=''; pref=''; hex='#00599C' }
  [pscustomobject]@{ file='debian'; group='international'; label='Debian'; kw='debian linux'; si='debian'; pkg=''; pref=''; hex='#A80030' }
  [pscustomobject]@{ file='fedora'; group='international'; label='Fedora'; kw='fedora linux'; si='fedora'; pkg=''; pref=''; hex='#51A2DA' }
  [pscustomobject]@{ file='centos'; group='international'; label='CentOS'; kw='centos linux'; si='centos'; pkg=''; pref=''; hex='#262577' }
  [pscustomobject]@{ file='archlinux'; group='international'; label='Arch Linux'; kw='archlinux linux'; si='archlinux'; pkg=''; pref=''; hex='#1793D1' }
  [pscustomobject]@{ file='redhat'; group='international'; label='Red Hat'; kw='redhat linux'; si='redhat'; pkg=''; pref=''; hex='#EE0000' }
  [pscustomobject]@{ file='googlecloud'; group='international'; label='Google Cloud'; kw='googlecloud gcp'; si='googlecloud'; pkg=''; pref=''; hex='#4285F4' }
  [pscustomobject]@{ file='digitalocean'; group='international'; label='DigitalOcean'; kw='digitalocean'; si='digitalocean'; pkg=''; pref=''; hex='#0080FF' }
  [pscustomobject]@{ file='sega'; group='international'; label='SEGA'; kw='sega game'; si='sega'; pkg=''; pref=''; hex='#250600' }
  [pscustomobject]@{ file='ubisoft'; group='international'; label='Ubisoft'; kw='ubisoft game'; si='ubisoft'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='ea'; group='international'; label='EA'; kw='ea electronicarts game'; si='ea'; pkg=''; pref=''; hex='#000000' }
  [pscustomobject]@{ file='rockstargames'; group='international'; label='Rockstar Games'; kw='rockstargames game'; si='rockstargames'; pkg=''; pref=''; hex='#FCAF23' }
  [pscustomobject]@{ file='battledotnet'; group='international'; label='Battle.net'; kw='battledotnet battle blizzard'; si='battledotnet'; pkg=''; pref=''; hex='#148EFF' }
  [pscustomobject]@{ file='kick'; group='international'; label='Kick'; kw='kick streaming'; si='kick'; pkg=''; pref=''; hex='#53FC18' }
  [pscustomobject]@{ file='geeksforgeeks'; group='international'; label='GeeksforGeeks'; kw='geeksforgeeks gfg'; si='geeksforgeeks'; pkg=''; pref=''; hex='#2F8D46' }
  [pscustomobject]@{ file='wireshark'; group='international'; label='Wireshark'; kw='wireshark'; si='wireshark'; pkg=''; pref=''; hex='#1679A9' }
  [pscustomobject]@{ file='filezilla'; group='international'; label='FileZilla'; kw='filezilla ftp'; si='filezilla'; pkg=''; pref=''; hex='#BF0000' }
  [pscustomobject]@{ file='virtualbox'; group='international'; label='VirtualBox'; kw='virtualbox vm'; si='virtualbox'; pkg=''; pref=''; hex='#183A61' }
  [pscustomobject]@{ file='apachekafka'; group='international'; label='Apache Kafka'; kw='apachekafka kafka'; si='apachekafka'; pkg=''; pref=''; hex='#231F20' }
  [pscustomobject]@{ file='rabbitmq'; group='international'; label='RabbitMQ'; kw='rabbitmq mq'; si='rabbitmq'; pkg=''; pref=''; hex='#FF6600' }
  [pscustomobject]@{ file='graphql'; group='international'; label='GraphQL'; kw='graphql api'; si='graphql'; pkg=''; pref=''; hex='#E10098' }
  [pscustomobject]@{ file='swagger'; group='international'; label='Swagger'; kw='swagger openapi'; si='swagger'; pkg=''; pref=''; hex='#85EA2D' }
  [pscustomobject]@{ file='anthropic'; group='international'; label='Anthropic'; kw='anthropic claude'; si='anthropic'; pkg=''; pref=''; hex='#191919' }
  [pscustomobject]@{ file='perplexity'; group='international'; label='Perplexity'; kw='perplexity'; si='perplexity'; pkg=''; pref=''; hex='#20808D' }
)

# ---------------- simple-icons 索引（title -> slug 派生 + slugs.md 例外） ----------------
Write-Host '读取 simple-icons 索引...'
$siJson = [IO.File]::ReadAllText((Join-Path $siDir 'data\simple-icons.json')) | ConvertFrom-Json
$slugsMd = [IO.File]::ReadAllText((Join-Path $siDir 'slugs.md'))
$slugException = @{}
foreach ($m in [regex]::Matches($slugsMd, '^\|\s*`([^`]+)`\s*\|\s*`([a-z0-9\-]+)`\s*\|\s*$', 'Multiline')) {
  $slugException[$m.Groups[1].Value] = $m.Groups[2].Value
}
$siHex = @{}
$siTitle = @{}
foreach ($i in $siJson) {
  $slug = if ($slugException.ContainsKey($i.title)) { $slugException[$i.title] } else { $i.title.ToLower() -replace '[^a-z0-9]', '' }
  if ($slug) {
    $siHex[$slug] = if ($i.hex -match '^#') { $i.hex } else { '#' + $i.hex }
    $siTitle[$slug] = $i.title
  }
}
Write-Host "  simple-icons: $($siHex.Count) 个图标"

# ---------------- lawnicons 索引（pkg -> drawable 计数） ----------------
Write-Host '读取 lawnicons appfilter.xml...'
$appfilter = [IO.File]::ReadAllText((Join-Path $lawnDir 'app\assets\appfilter.xml'))
$pkgDrawables = @{}
foreach ($m in [regex]::Matches($appfilter, 'component="ComponentInfo\{([^/}]+)/[^}]+\}"\s+drawable="([^"]+)"')) {
  $pkg = $m.Groups[1].Value
  $d = $m.Groups[2].Value
  if (-not $pkgDrawables.ContainsKey($pkg)) { $pkgDrawables[$pkg] = @{} }
  if ($pkgDrawables[$pkg].ContainsKey($d)) { $pkgDrawables[$pkg][$d]++ } else { $pkgDrawables[$pkg][$d] = 1 }
}
Write-Host "  lawnicons: $($pkgDrawables.Count) 个应用包"

function Pick-Drawable([string]$pkg, [string]$pref) {
  if (-not $pkg -or -not $pkgDrawables.ContainsKey($pkg)) { return $null }
  $set = $pkgDrawables[$pkg]
  if ($pref -and $set.ContainsKey($pref)) { return $pref }
  $best = $null; $bestCount = -1
  foreach ($k in $set.Keys) {
    if ($set[$k] -gt $bestCount) { $best = $k; $bestCount = $set[$k] }
  }
  return $best
}

# ---------------- 查找模式 ----------------
if ($Find) {
  Write-Host "--- lawnicons 包名/drawable 匹配 '$Find' ---"
  foreach ($k in $pkgDrawables.Keys) {
    if ($k -like "*$Find*") {
      $top = ($pkgDrawables[$k].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 2 | ForEach-Object { "$($_.Key)x$($_.Value)" }) -join ','
      Write-Host "  $k -> $top"
    }
  }
  Write-Host "--- simple-icons 匹配 '$Find' ---"
  foreach ($s in $siHex.Keys) {
    if ($s -like "*$Find*" -or $siTitle[$s] -like "*$Find*") { Write-Host "  $s ($($siTitle[$s])) $($siHex[$s])" }
  }
  return
}

# ---------------- SVG 处理 ----------------
# 提取原 svg 内部全部图形（path/circle/rect/g 等，支持 stroke 型），上品牌色，
# 按原 viewBox 等比缩放到 112x112 居中放入 128x128 透明画布（边距 8）
function Convert-ToBrandSvg([string]$svg, [string]$hex) {
  if (-not $svg) { return $null }
  $rootOpen = [regex]::Match($svg, '<svg\b[^>]*>')
  if (-not $rootOpen.Success) { return $null }
  $rootTag = $rootOpen.Value
  $start = $rootOpen.Index + $rootOpen.Length
  $end = $svg.LastIndexOf('</svg>')
  if ($end -lt $start) { return $null }
  $inner = $svg.Substring($start, $end - $start)
  $inner = [regex]::Replace($inner, '(?s)<!--.*?-->', '')
  $inner = [regex]::Replace($inner, '(?s)<title>.*?</title>', '')
  $inner = [regex]::Replace($inner, '(?s)<metadata>.*?</metadata>', '')
  $inner = [regex]::Replace($inner, '(?s)<desc>.*?</desc>', '')
  if ($inner -notmatch '<(path|circle|rect|ellipse|polygon|polyline|line|g)\b') { return $null }
  # 原始 viewBox（缺省时用 width/height，再缺省按 24x24）
  $minX = 0.0; $minY = 0.0; $w = 24.0; $h = 24.0
  $vb = [regex]::Match($rootTag, 'viewBox="([\-0-9.eE]+)\s+([\-0-9.eE]+)\s+([\-0-9.eE]+)\s+([\-0-9.eE]+)"')
  if ($vb.Success) {
    $minX = [double]$vb.Groups[1].Value; $minY = [double]$vb.Groups[2].Value
    $w = [double]$vb.Groups[3].Value; $h = [double]$vb.Groups[4].Value
  } else {
    $mw = [regex]::Match($rootTag, 'width="([0-9.]+)')
    $mh = [regex]::Match($rootTag, 'height="([0-9.]+)')
    if ($mw.Success -and $mh.Success) { $w = [double]$mw.Groups[1].Value; $h = [double]$mh.Groups[1].Value }
  }
  if ($w -le 0 -or $h -le 0) { return $null }
  # 根节点 fill/stroke 继承（stroke 型图标常把 stroke/stroke-width 定义在根 <svg> 上，丢弃根节点后需补回）
  $rootFill = [regex]::Match($rootTag, '(?i)\bfill\s*=\s*"([^"]*)"').Groups[1].Value
  $rootStroke = [regex]::Match($rootTag, '(?i)\bstroke\s*=\s*"([^"]*)"').Groups[1].Value
  if ($rootFill -or $rootStroke) {
    $wrapAttrs = ''
    if ($rootFill -ieq 'none') { $wrapAttrs += ' fill="none"' }
    elseif ($rootFill -and $rootFill -ine 'none') { $wrapAttrs += ' fill="' + $hex + '"' }
    if ($rootStroke -ieq 'none') { $wrapAttrs += ' stroke="none"' }
    elseif ($rootStroke) { $wrapAttrs += ' stroke="' + $hex + '"' }
    foreach ($sa in @('stroke-width', 'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'stroke-dasharray', 'stroke-dashoffset', 'stroke-opacity')) {
      $mv = [regex]::Match($rootTag, '(?i)\b' + $sa + '\s*=\s*"([^"]*)"')
      if ($mv.Success) { $wrapAttrs += ' ' + $sa + '="' + $mv.Groups[1].Value + '"' }
    }
    $inner = '<g' + $wrapAttrs + '>' + $inner + '</g>'
  }
  # 上色：非 none 的 fill/stroke 全部替换为品牌色
  $inner = [regex]::Replace($inner, '(?i)fill\s*=\s*"(?!none)[^"]*"', 'fill="' + $hex + '"')
  $inner = [regex]::Replace($inner, '(?i)stroke\s*=\s*"(?!none)[^"]*"', 'stroke="' + $hex + '"')
  # 等比缩放居中（透明背景，图形区域 112x112，边距 8）
  $s = 112.0 / [Math]::Max($w, $h)
  $tx = 8 + (112 - $w * $s) / 2 - $minX * $s
  $ty = 8 + (112 - $h * $s) / 2 - $minY * $s
  $sf = '{0:0.####}' -f $s; $txf = '{0:0.####}' -f $tx; $tyf = '{0:0.####}' -f $ty
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">' +
    '<g transform="translate(' + $txf + ' ' + $tyf + ') scale(' + $sf + ')" fill="' + $hex + '">' + $inner + '</g></svg>'
}

# ---------------- 深色图标可见性处理 ----------------
# 近黑中性色品牌图标（apple/X/Notion/Steam 等官方色为纯黑）在深色主题下不可见：
# 通道差 ≤26（中性色）且亮度 <0.22（近黑）时统一提亮为 #737373 中性灰，保证双主题可见；
# 彩色深色（slack 紫、openai 蓝紫等）保留原色
function Normalize-Hex([string]$hex) {
  if ($hex -notmatch '^#[0-9a-fA-F]{6}$') { return $hex }
  $r = [Convert]::ToInt32($hex.Substring(1, 2), 16)
  $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
  $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)
  $max = [Math]::Max($r, [Math]::Max($g, $b)); $min = [Math]::Min($r, [Math]::Min($g, $b))
  $lum = (0.2126 * $r + 0.7152 * $g + 0.0722 * $b) / 255.0
  if (($max - $min) -le 26 -and $lum -lt 0.22) { return '#737373' }
  return $hex
}

# ---------------- 生成 ----------------
$results = @()
foreach ($e in $manifest) {
  $svg = $null; $hex = $null; $src = ''
  $siPath = if ($e.si) { Join-Path $siDir ("icons\" + $e.si + ".svg") } else { $null }
  if ($siPath -and (Test-Path -LiteralPath $siPath) -and $siHex.ContainsKey($e.si)) {
    $svg = [IO.File]::ReadAllText($siPath)
    if ($svg) { $hex = if ($e.force) { $e.hex } else { $siHex[$e.si] }; $src = "si:$($e.si)" }
  }
  if (-not $svg) {
    $drawable = Pick-Drawable $e.pkg $e.pref
    if ($drawable) {
      $lawnPath = Join-Path $lawnDir ("svgs\" + $drawable + ".svg")
      if (Test-Path -LiteralPath $lawnPath) {
        $svg = [IO.File]::ReadAllText($lawnPath)
        if ($svg) { $hex = $e.hex; $src = "lawn:$drawable" }
      }
    }
  }
  if (-not $svg) {
    $results += [pscustomobject]@{ file = $e.file; label = $e.label; status = 'MISS'; source = '' }
    continue
  }
  $hex = Normalize-Hex $hex
  $out = Convert-ToBrandSvg $svg $hex
  if (-not $out) {
    $results += [pscustomobject]@{ file = $e.file; label = $e.label; status = 'NOPATH'; source = $src }
    continue
  }
  [IO.File]::WriteAllText((Join-Path $outDir "$($e.file).svg"), $out, [Text.UTF8Encoding]::new($false))
  $results += [pscustomobject]@{ file = $e.file; label = $e.label; status = 'OK'; source = $src }
}

Write-Host ''
$results | Format-Table -AutoSize
$okCount = ($results | Where-Object status -eq 'OK').Count
$failCount = ($results | Where-Object { $_.status -ne 'OK' }).Count
Write-Host "完成: OK=$okCount, 失败=$failCount, 输出目录: $outDir"

# 写出成功清单供 BrandIcons.ets 注册表参考
$okManifest = @()
foreach ($e in $manifest) {
  $r = $results | Where-Object file -eq $e.file | Select-Object -First 1
  if ($r -and $r.status -eq 'OK') {
    $okManifest += [pscustomobject]@{ file = $e.file; group = $e.group; label = $e.label; kw = $e.kw; source = $r.source }
  }
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'brand-icons-manifest.json'),
  ($okManifest | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
Write-Host "清单已写入: $PSScriptRoot\brand-icons-manifest.json"
