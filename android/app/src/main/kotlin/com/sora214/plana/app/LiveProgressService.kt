package com.sora214.plana.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/**
 * 生成进度前台服务:切后台不被杀 + 独占一条常驻通知。
 *
 * 两条通道分工:`gen_progress`(LOW)静默常驻、负责进度与上岛;`gen_done`(HIGH)
 * 只在收尾时发一条,会弹横幅出声。理由见 [settle] 与 [ensureDoneChannel]。
 *
 * 分档渲染(能力探测 + 优雅降级):
 *  - API 36+：Notification.ProgressStyle + setRequestPromotedOngoing → 系统可提升到
 *    状态栏胶囊 / 锁屏 / AOD;三星 One UI 8、OPPO ColorOS 16 等灵动岛会自动采纳这套标准。
 *  - 低版本：ProgressStyle 由 androidx 自动回落成 setProgress 进度条(可见,只是不上岛)。
 *
 * 由 MethodChannel 经 companion 驱动。update/finish/stop 直接操作运行中的实例,
 * 避免"后台 startService"限制;仅 start 用 startForegroundService 拉起。
 * 生成逻辑仍在 Flutter 主 isolate,本服务只负责进程保活与通知。
 */
class LiveProgressService : Service() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_START) {
            handler.removeCallbacksAndMessages(null) // 上一轮的完成态收尾作废
            nm().cancel(DONE_ID) // 又开始生成了,上一张的「完成」已经过期
            val title = intent.getStringExtra(EXTRA_TITLE) ?: "Plana"
            val text = intent.getStringExtra(EXTRA_TEXT) ?: ""
            val total = intent.getIntExtra(EXTRA_TOTAL, 0)
            val short = intent.getStringExtra(EXTRA_SHORT) ?: ""
            // total>0:准备态即用确定进度条(0/total),从一开始就能上岛
            startInForeground(build(title, text, 0, total, indeterminate = total <= 0, shortText = short, ongoing = true))
            // startForegroundService 是异步的:服务起来之前 Flutter 侧推的进度/收尾
            // 全被 companion 暂存在这里。不补发就会丢掉开头那几百毫秒的更新,
            // 更糟的是丢掉 finish/stop —— 那条常驻通知会永远挂着。
            val p = pending
            pending = null
            p?.invoke(this)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        if (instance === this) instance = null
        super.onDestroy()
    }

    // —— 实例侧:被 companion 直接调用 ——

    fun applyUpdate(
        cur: Int,
        total: Int,
        indeterminate: Boolean,
        title: String,
        text: String,
        shortText: String,
    ) {
        handler.removeCallbacksAndMessages(null) // 又有新进度:完成态收尾作废
        nm().notify(NOTIF_ID, build(title, text, cur, total, indeterminate, shortText, ongoing = true))
    }

    /**
     * 收尾。[keep] 为 true 时终态留一条可点开的通知(应用在后台,用户需要入口回来);
     * 为 false 时终态通知撤掉(应用在前台,结果已经在眼前)。
     *
     * 先把常驻态改成「完成」停留几秒再落地 —— 否则岛是**直接消失**的,用户只看到
     * 生成中忽然没了,没有任何完成反馈。停留期间服务仍是前台服务,延时任务保证跑得到。
     *
     * **不按 [canPromote] 分档。** 那个只认 AOSP 的 promoted ongoing(API 36+),
     * 而小米/华为等的灵动岛是各家自己的私有实现,在低版本上照样有岛却一律探测为
     * false —— 按它分档等于在真有岛的机器上把完成反馈关掉。没岛的机器代价也只是
     * 通知条多显示 4 秒「完成 + 满进度条」,本来就是实话。
     *
     * [next] 非空 = 还有别的在跑(AI 助手):落地时服务不停,常驻那条换成 [next] 的不确定态。
     */
    fun applyFinish(
        title: String,
        text: String,
        shortText: String,
        keep: Boolean,
        next: String,
        nextShort: String,
    ) {
        handler.removeCallbacksAndMessages(null)
        nm().notify(
            NOTIF_ID,
            build(title, text, 1, 1, indeterminate = false, shortText = shortText, ongoing = true),
        )
        handler.postDelayed({ settle(title, text, keep, next, nextShort) }, HOLD_MS)
    }

    /**
     * 终态落地:撤掉常驻那条,[keep] 时另发一条「完成」通知,脱离前台并停服务。
     *
     * 完成走**另一个通道**(DONE_CHANNEL_ID,IMPORTANCE_HIGH)而不是原地改那条常驻的:
     *  - 进度通道是 IMPORTANCE_LOW,静默不弹横幅 —— 一秒刷一次的进度条要是会弹,
     *    每次点生成都糊你自己一脸;
     *  - 而且 setOnlyAlertOnce(true) 下,同一条通知只在**首次**出现时提醒。原地改
     *    的话提醒发生在「开始」,真正该提醒的「完成」反而一声不吭,正好反了。
     * 两条通道各司其职:进度静默常驻,完成弹横幅。
     */
    private fun settle(title: String, text: String, keep: Boolean, next: String, nextShort: String) {
        val handoff = next.isNotEmpty()
        if (!handoff) stopForegroundCompat(removeNotification = true)
        if (keep) {
            ensureChannels(this)
            val b = NotificationCompat.Builder(this, DONE_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_gen)
                .setContentTitle(title)
                .setAutoCancel(true)
                .setContentIntent(openIntent())
                // 26 以下没有通道,横幅只能靠 priority(minSdk 24 仍要管)。
                // 不设 defaults —— 那会把声音振动加回来,与通道那边的静默不一致。
                .setPriority(NotificationCompat.PRIORITY_HIGH)
            if (text.isNotEmpty()) b.setContentText(text)
            nm().notify(DONE_ID, b.build())
        }
        if (handoff) {
            nm().notify(
                NOTIF_ID,
                build(next, "", 0, 0, indeterminate = true, shortText = nextShort, ongoing = true),
            )
            return
        }
        stopSelf()
    }

    /** 静默停止:直接撤掉通知与服务(用户取消 / 无需完成反馈时用)。 */
    fun applyStop() {
        handler.removeCallbacksAndMessages(null)
        stopForegroundCompat(removeNotification = true)
        stopSelf()
    }

    // —— 通知构造 ——

    private fun build(
        title: String,
        text: String,
        cur: Int,
        total: Int,
        indeterminate: Boolean,
        shortText: String,
        ongoing: Boolean,
    ): Notification {
        ensureChannels(this)
        val b = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_gen)
            .setContentTitle(title)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setOnlyAlertOnce(true)
            .setContentIntent(openIntent())
        // 标题已经带状态("生成中 12/28"),副文案为空时不占一行 ——
        // 空串会被渲染成一行空白,把卡片撑高。
        if (text.isNotEmpty()) b.setContentText(text)

        // API 36+ 的常驻(ongoing)态一律请求上岛,从「准备」起就显示状态栏胶囊,
        // 而不是等有了确定步数才提升——否则单图很快,岛只会在末尾一闪。
        val promote = Build.VERSION.SDK_INT >= 36 && ongoing
        if (ongoing) {
            // 不确定态也走 ProgressStyle。上岛资格本身不要求它(Standard Style 也在
            // 白名单里),但整条生命周期用同一个 style,岛和通知卡才不会在「排队 →
            // 出图」那一刻换一副样子重新排版。
            // 低于 36 时 androidx 自己把 ProgressStyle 翻译回 setProgress,不受影响。
            val style = NotificationCompat.ProgressStyle()
            if (total > 0 && !indeterminate) {
                style
                    .setProgressSegments(listOf(NotificationCompat.ProgressStyle.Segment(total)))
                    .setProgress(cur.coerceIn(0, total))
            } else {
                // 段长只是为了让轨道有长度(不确定态下进度值本身不显示)
                style
                    .setProgressSegments(listOf(NotificationCompat.ProgressStyle.Segment(100)))
                    .setProgressIndeterminate(true)
            }
            b.setStyle(style)
        }
        // 终态(!ongoing)不设任何 style:一条「生成完成」下面还挂着跑马灯进度条,
        // 是旧实现掉进 indeterminate 分支的结果,不是想要的样子。
        if (promote) {
            if (shortText.isNotEmpty()) b.setShortCriticalText(shortText)
            b.setRequestPromotedOngoing(true)
        }
        return b.build()
    }

    private fun openIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        packageManager.getLaunchIntentForPackage(packageName),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun nm() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun startInForeground(notif: Notification) {
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    private fun stopForegroundCompat(removeNotification: Boolean) {
        if (Build.VERSION.SDK_INT >= 24) {
            stopForeground(if (removeNotification) STOP_FOREGROUND_REMOVE else STOP_FOREGROUND_DETACH)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(removeNotification)
        }
    }

    companion object {
        const val CHANNEL_ID = "gen_progress"

        /**
         * 完成通道。**id 带版本号,改配置就得换 id。**
         *
         * `createNotificationChannel` 对已存在的 id 只更新名字/描述/分组 ——
         * importance、声音、振动一律忽略(那些归用户管,应用改不动)。删掉再同 id
         * 重建也不行:系统只是把它标记为「未删除」,旧配置原样回来。所以每次改
         * 默认配置都只能进版本号,并把历史 id 删掉别在设置里留死条目。
         */
        const val DONE_CHANNEL_ID = "gen_done_v3"
        private val LEGACY_DONE_CHANNEL_IDS = listOf("gen_done", "gen_done_v2")

        const val NOTIF_ID = 4711
        const val DONE_ID = 4712

        /** 完成态在岛上停留多久再落地。够看清一眼,又不至于赖着不走。 */
        private const val HOLD_MS = 4000L

        private const val ACTION_START = "com.sora214.plana.app.LIVE_START"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"
        private const val EXTRA_TOTAL = "total"
        private const val EXTRA_SHORT = "short"

        /**
         * 建好两条通道。**应用启动时就调一次**,而不是等第一次生成 ——
         * 通道不存在,系统设置里的「通知类别」就是空的,用户在真正用到之前
         * 根本没法预先配置声音/振动/横幅。
         *
         * 分工:进度 LOW 全程静默(一秒刷一次,弹横幅是灾难);完成 HIGH 但也静默,
         * 只弹一张不响不振的横幅。想要声音/振动的用户自己在系统设置里开。
         */
        /** 两条通道的名字与说明换成界面语言(同 id 重建只更新这几项)。 */
        fun setChannelNames(ctx: Context, progress: String, progressDesc: String, done: String, doneDesc: String) {
            if (Build.VERSION.SDK_INT < 26) return
            ensureChannels(ctx)
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, progress, NotificationManager.IMPORTANCE_LOW)
                    .apply { description = progressDesc },
            )
            nm.createNotificationChannel(
                NotificationChannel(DONE_CHANNEL_ID, done, NotificationManager.IMPORTANCE_HIGH)
                    .apply { description = doneDesc },
            )
        }

        fun ensureChannels(ctx: Context) {
            if (Build.VERSION.SDK_INT < 26) return
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(CHANNEL_ID, "生成进度", NotificationManager.IMPORTANCE_LOW)
                ch.description = "生成期间的常驻进度条(静默)"
                ch.setShowBadge(false)
                nm.createNotificationChannel(ch)
            }
            if (nm.getNotificationChannel(DONE_CHANNEL_ID) == null) {
                LEGACY_DONE_CHANNEL_IDS.forEach(nm::deleteNotificationChannel)
                val ch = NotificationChannel(DONE_CHANNEL_ID, "生成完成", NotificationManager.IMPORTANCE_HIGH)
                ch.description = "出图 / 队列 / 循环结束时提醒一次"
                // 静默横幅:弹出来看得见,但不响不振不闪。振动和呼吸灯默认就是关的,
                // 不碰即可;**声音得显式关** —— NotificationChannel 构造时会把 mSound
                // 填成系统默认提示音,HIGH 档下不置空就会响。
                ch.setSound(null, null)
                nm.createNotificationChannel(ch)
            }
        }

        @Volatile
        private var instance: LiveProgressService? = null

        /** 服务还没起来时收到的最后一条指令,onStartCommand 里补发。 */
        @Volatile
        private var pending: ((LiveProgressService) -> Unit)? = null

        private fun post(action: (LiveProgressService) -> Unit) {
            val s = instance
            if (s == null) {
                pending = action
            } else {
                pending = null
                action(s)
            }
        }

        fun start(ctx: Context, title: String?, text: String?, total: Int, short: String?) {
            pending = null // 新一轮,上一轮没送达的指令作废
            val i = Intent(ctx, LiveProgressService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_TEXT, text)
                putExtra(EXTRA_TOTAL, total)
                putExtra(EXTRA_SHORT, short)
            }
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun update(
            cur: Int,
            total: Int,
            indeterminate: Boolean,
            title: String,
            text: String,
            shortText: String,
        ) = post { it.applyUpdate(cur, total, indeterminate, title, text, shortText) }

        fun finish(
            title: String,
            text: String,
            shortText: String,
            keep: Boolean,
            next: String,
            nextShort: String,
        ) = post { it.applyFinish(title, text, shortText, keep, next, nextShort) }

        fun stop() = post { it.applyStop() }

        /** 该设备/权限下能否真正上岛(API 36 promoted)。供 Dart 探测降级。 */
        fun canPromote(ctx: Context): Boolean {
            if (Build.VERSION.SDK_INT < 36) return false
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return nm.canPostPromotedNotifications()
        }
    }
}
