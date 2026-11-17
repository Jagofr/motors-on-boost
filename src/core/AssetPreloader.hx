package core;

import config.GameConfig;
import config.GameConfig.IntroConfig;
import ui.nodes.UINodes.UITile as Tile;

/** Callback signature invoked when an asset URL resolves or fails to decode. */
typedef AssetTileCallback = Null<Tile> -> Void;

/**
 * Background asset preloader managing asynchronous asset warming and readiness tracking
 * for the boot splash sequence without blocking or referencing Heaps/DOM APIs directly.
 */
class AssetPreloader {
    private static var sharedTileCache:Map<String, Tile> = new Map<String, Tile>();

    public var config:IntroConfig;
    public var totalTasks(default, null):Int = 0;
    public var completedTasks(default, null):Int = 0;
    public var isStarted(default, null):Bool = false;
    public var isComplete(default, null):Bool = false;
    public var onAllLoaded:Null<Void -> Void> = null;

    private var loadingUrls:Map<String, Bool> = new Map<String, Bool>();
    private var waiters:Map<String, Array<AssetTileCallback>> = new Map<String, Array<AssetTileCallback>>();

    public function new(?config:IntroConfig) {
        this.config = config != null ? config : GameConfig.getDefault().intro;
    }

    /** Kicks off non-blocking warmup of splash/touch asset URLs and invokes optional world warmup. */
    public function start(?worldWarmup:Void -> Void):Void {
        if (isStarted) return;
        isStarted = true;

        var urls:Array<String> = [];
        urls.push(config.studioSplashPath);
        urls.push(config.engineSplashPath);
        for (p in config.engineLogoPaths) urls.push(p);
        for (p in config.touchIconPaths) urls.push(p);

        for (u in urls) preloadImage(u);

        if (worldWarmup != null) {
            var finishWarmup = beginExternalTask();
            worldWarmup();
            finishWarmup();
        } else {
            checkCompletion();
        }
    }

    public function beginExternalTask():Void -> Void {
        totalTasks++;
        var doneCalled = false;
        return function() {
            if (!doneCalled) {
                doneCalled = true;
                completedTasks++;
                checkCompletion();
            }
        };
    }

    public function getProgress():Float {
        if (totalTasks <= 0) return isStarted ? 1.0 : 0.0;
        return Math.min(1.0, completedTasks / totalTasks);
    }

    public static function getCachedTile(path:String):Null<Tile> {
        if (path == null) return null;
        return sharedTileCache.get(path);
    }

    public static function cacheTile(path:String, tile:Tile):Void {
        if (path != null && tile != null) {
            sharedTileCache.set(path, tile);
        }
    }

    public static function tryLoadEmbeddedTile(path:String):Null<Tile> {
        return getCachedTile(path);
    }

    public function onTileReady(url:String, cb:AssetTileCallback):Void {
        if (url == null || cb == null) return;
        var cached = getCachedTile(url);
        if (cached != null) {
            cb(cached);
            return;
        }
        var list = waiters.get(url);
        if (list == null) {
            list = [];
            waiters.set(url, list);
        }
        list.push(cb);
        preloadImage(url);
    }

    public function preloadImage(url:String):Void {
        if (url == null || url == "") return;
        if (getCachedTile(url) != null || loadingUrls.exists(url)) return;

        loadingUrls.set(url, true);
        totalTasks++;

        // Signal browser preload queue (DOM images/logos load inside ui-overlay.js)
        WebBridge.inst.pushEvent({ type: "preload_asset", url: url });

        var tile = Tile.fromColor(0xFFFFFFFF, 256, 256, 1.0);
        tile.url = url;
        cacheTile(url, tile);

        completedTasks++;
        notifyWaiters(url, tile);
        checkCompletion();
    }

    private function notifyWaiters(url:String, tile:Null<Tile>):Void {
        var list = waiters.get(url);
        if (list != null) {
            waiters.remove(url);
            for (cb in list) cb(tile);
        }
    }

    private function checkCompletion():Void {
        if (isStarted && !isComplete && completedTasks >= totalTasks) {
            isComplete = true;
            if (onAllLoaded != null) onAllLoaded();
        }
    }

    public static function resetSharedCache():Void {
        sharedTileCache.clear();
    }
}
