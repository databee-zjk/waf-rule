




1. readme 内容必须精炼；主要说明如何应用；
因为现在脚本 名 已经足够明确说明 是什么；
不用说太多生成这些脚本的经过；

2. 说出日常可以怎么部署应用；

3. 新增一个report.md；

3.1 当前期望一个可测试的aws真实列表节点，用以测试waf-ipset是否work；
3.2 期望传统linux crontab 还是 lambda，如果后者，再推进；如果是我个人，基本以服务器管理为主；
3.3 当前的材料基本就这些，看有什么期望补充；

----------

增加一个todoList；

先增加第一个， 异常hook，便于其他脚本对接，例如slack 告警之类的；类似exception，。提供一个其他脚本容易监控的手段，也可以是规范；
例如，其他文件可以grep run.log查看是否有前一天的异常log grep 前一天 |grep exception;
又例如，可以设定   handler脚本配置； handler.sh exception

主要是，先形成todolist.md，先不用执行，意思是跟报告差不多，让上头看是否期望推进