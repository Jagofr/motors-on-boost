package core;

import config.GameConfig;
import config.GameConfig.IntroConfig;

/**
 * Callback signature invoked when an individual bitmap resource resolves into a tile.
 *
 * @callback AssetTileCallback
 * @param {Null<h2d.Tile>} tile Decoded 2D tile or null if unavailable.
 */
typedef AssetTileCallback = Null<h2d.Tile> -> Void;

/**
 * Background asset preloader managing asynchronous texture decoding and resource
 * warm-up during boot screens without exposing any progress bar UI.
 *
 * @class AssetPreloader
 * @module core/AssetPreloader
 */
class AssetPreloader {
    /** Global tile cache keyed by normalized asset path. */
    private static var sharedTileCache:Map<String, h2d.Tile> = new Map<String, h2d.Tile>();

    /** Active intro and preloader configuration profile. */
    public var config:IntroConfig;

    /** Total asynchronous tasks scheduled in the current boot cycle. */
    public var totalTasks(default, null):Int = 0;

    /** Number of tasks resolved cleanly (loaded or gracefully timed out). */
    public var completedTasks(default, null):Int = 0;

    /** True once background preloading has started. */
    public var isStarted(default, null):Bool = false;

    /** True once every queued asset and world warm-up task has completed. */
    public var isComplete(default, null):Bool = false;

    /** Optional listener notified when every queued task completes. */
    public var onAllLoaded:Null<Void -> Void> = null;

    /** Active open task tokens remaining before completion triggers. */
    private var openHandles:Int = 0;

    /** Prevents duplicate world warm-up invocations. */
    private var warmupExecuted:Bool = false;

    /** Pending callbacks waiting on asynchronous WebP decode completion. */
    private var tileWaiters:Map<String, Array<AssetTileCallback>> = new Map<String, Array<AssetTileCallback>>();

    /**
     * Creates a new background AssetPreloader instance.
     *
     * @param {Null<IntroConfig>} [config] Optional intro asset path configuration.
     */
    public function new(?config:IntroConfig) {
        this.config = config != null ? config : GameConfig.getDefault().intro;
    }

    /**
     * Begins asynchronous background preloading of intro imagery, logo icons,
     * touch control sprites, and deferred 3D world initialization immediately at boot.
     *
     * @param {Null<Void -> Void>} [worldWarmup] Optional 3D world preparation callback run in background.
     * @returns {Void}
     */
    public function start(?worldWarmup:Void -> Void):Void {
        if (isStarted) return;
        isStarted = true;
        isComplete = false;

        // 1. Decode all intro WebP and badge assets asynchronously
        preloadWebpImage(config.studioSplashPath);
        preloadWebpImage(config.engineSplashPath);
        for (logoPath in config.engineLogoPaths) {
            preloadWebpImage(logoPath);
        }

        // 2. Warm embedded touch HUD textures if Heaps resource loader is active
        warmEmbeddedTouchIcons();

        // 3. Schedule 3D world construction asynchronously so Publisher screen renders on frame 1
        if (worldWarmup != null && !warmupExecuted) {
            warmupExecuted = true;
            var done = beginExternalTask();
            #if js
            js.Browser.window.setTimeout(function() {
                try {
                    worldWarmup();
                } catch (e:Dynamic) {
                    trace("[AssetPreloader] World warmup error: " + e);
                }
                done();
            }, 30);
            #else
            worldWarmup();
            done();
            #end
        }

        checkCompletion();
    }

    /**
     * Reserves an external asynchronous loading token and returns its idempotent resolver.
     *
     * @returns {Void -> Void} Completion function that decrements openHandles once.
     */
    public function beginExternalTask():Void -> Void {
        totalTasks++;
        openHandles++;
        isComplete = false;
        var finished = false;
        return function() {
            if (finished) return;
            finished = true;
            completedTasks++;
            openHandles--;
            if (openHandles < 0) openHandles = 0;
            checkCompletion();
        };
    }

    /**
     * Retrieves a previously cached tile by path.
     *
     * @param {String} path Relative asset path key.
     * @returns {Null<h2d.Tile>} Cached tile or null if absent.
     */
    public static function getCachedTile(path:String):Null<h2d.Tile> {
        return sharedTileCache.get(path);
    }

    /**
     * Inserts a resolved tile into the static shared cache.
     *
     * @param {String} path Relative asset path key.
     * @param {h2d.Tile} tile Resolved Heaps tile.
     * @returns {Void}
     */
    public static function cacheTile(path:String, tile:h2d.Tile):Void {
        if (tile != null) {
            sharedTileCache.set(path, tile);
        }
    }

    /**
     * Attempts to load an embedded Heaps resource safely without throwing or logging
     * errors when executed under headless unit test harnesses lacking hxd.Res init.
     *
     * @param {String} path Relative path inside res/.
     * @returns {Null<h2d.Tile>} Resolved tile or null if loader is uninitialized/missing.
     */
    public static function tryLoadEmbeddedTile(path:String):Null<h2d.Tile> {
        var existing = sharedTileCache.get(path);
        if (existing != null) return existing;

        try {
            var loader = hxd.Res.loader;
            if (loader == null) return null;
            var res = loader.load(path);
            if (res == null) return null;
            var tile = res.toTile();
            if (tile != null) {
                sharedTileCache.set(path, tile);
            }
            return tile;
        } catch (e:Dynamic) {
            return null;
        }
    }

    /**
     * Subscribes a callback notified immediately if cached, or once background decode finishes.
     *
     * @param {String} url Image asset URL.
     * @param {AssetTileCallback} cb Callback invoked with decoded tile or null.
     * @returns {Void}
     */
    public function onTileReady(url:String, cb:AssetTileCallback):Void {
        var cached = sharedTileCache.get(url);
        if (cached != null) {
            cb(cached);
            return;
        }
        var list = tileWaiters.get(url);
        if (list == null) {
            list = [];
            tileWaiters.set(url, list);
        }
        list.push(cb);
    }

    /**
     * Preloads configured embedded touch control icons into shared memory cache.
     *
     * @returns {Void}
     */
    private function warmEmbeddedTouchIcons():Void {
        for (iconPath in config.touchIconPaths) {
            tryLoadEmbeddedTile(iconPath);
        }
    }

    /**
     * Loads and rasterizes a Web/WebP bitmap via HTML5 Image and offscreen Canvas into
     * GPU texture memory. Safely resolves immediately on non-DOM headless targets.
     *
     * @param {String} url Relative image URL to decode.
     * @returns {Void}
     */
    private function preloadWebpImage(url:String):Void {
        var cached = sharedTileCache.get(url);
        if (cached != null) {
            notifyWaiters(url, cached);
            return;
        }

        var done = beginExternalTask();
        #if js
        try {
            var img = new js.html.Image();
            img.onload = function(_) {
                var tile:Null<h2d.Tile> = null;
                try {
                    var w = img.naturalWidth > 0 ? img.naturalWidth : img.width;
                    var h = img.naturalHeight > 0 ? img.naturalHeight : img.height;
                    var canvas = js.Browser.document.createCanvasElement();
                    canvas.width = w;
                    canvas.height = h;
                    var ctx = canvas.getContext2d();
                    ctx.drawImage(img, 0, 0);
                    var imageData = ctx.getImageData(0, 0, w, h);
                    var bytes = haxe.io.Bytes.ofData(imageData.data.buffer);
                    var bmp = new hxd.BitmapData(w, h);
                    bmp.setPixels(new hxd.Pixels(w, h, bytes, hxd.PixelFormat.RGBA));
                    var tex = h3d.mat.Texture.fromBitmap(bmp);
                    tile = h2d.Tile.fromTexture(tex);
                    cacheTile(url, tile);
                } catch (e:Dynamic) {
                    trace("[AssetPreloader] Rasterization error for " + url + ": " + e);
                }
                notifyWaiters(url, tile);
                done();
            };
            img.onerror = function(_) {
                trace("[AssetPreloader] WebP load failure for: " + url);
                notifyWaiters(url, null);
                done();
            };
            img.src = url;
        } catch (e:Dynamic) {
            notifyWaiters(url, null);
            done();
        }
        #else
        notifyWaiters(url, null);
        done();
        #end
    }

    /**
     * Invokes and drains registered waiters for a decoded image path.
     *
     * @param {String} url Resolved asset path.
     * @param {Null<h2d.Tile>} tile Resolved tile or null.
     * @returns {Void}
     */
    private function notifyWaiters(url:String, tile:Null<h2d.Tile>):Void {
        var waiters = tileWaiters.get(url);
        if (waiters != null) {
            tileWaiters.remove(url);
            for (cb in waiters) {
                cb(tile);
            }
        }
    }

    /**
     * Evaluates completion state and invokes `onAllLoaded` once openHandles reaches zero.
     *
     * @returns {Void}
     */
    private function checkCompletion():Void {
        if (isStarted && !isComplete && openHandles <= 0) {
            isComplete = true;
            if (onAllLoaded != null) {
                onAllLoaded();
            }
        }
    }
}
