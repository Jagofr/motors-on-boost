package world;

import math.Vec3;

/**
 * Polymorphic terrain and track surface contract decoupling `CarPhysics`
 * from specific map implementations (`Track`, `SandboxMap`, etc.).
 *
 * @interface IGroundProvider
 * @module world/IGroundProvider
 */
interface IGroundProvider {
    /**
     * Evaluates continuous ground surface Z elevation beneath world coordinate `(x, y)`.
     *
     * @param {Float} x World X coordinate in meters.
     * @param {Float} y World Y coordinate in meters.
     * @returns {Float} Ground surface Z elevation in meters.
     */
    public function getGroundElevation(x:Float, y:Float):Float;

    /**
     * Computes unit surface normal vector beneath `(x, y)`.
     *
     * @param {Float} x World X coordinate in meters.
     * @param {Float} y World Y coordinate in meters.
     * @param {Vector} outNormal Scratch vector populated in-place with surface normal.
     * @returns {Void}
     */
    public function getGroundNormal(x:Float, y:Float, outNormal:Vec3):Void;

    /**
     * Evaluates local surface tire friction multiplier (`mu`).
     *
     * @param {Float} x World X coordinate in meters.
     * @param {Float} y World Y coordinate in meters.
     * @returns {Float} Friction scalar (1.0 = nominal dry asphalt).
     */
    public function getGroundFriction(x:Float, y:Float):Float;

    /**
     * Enforces arena perimeter walls or trackside barriers, clamping `pos` and returning rebound factors.
     *
     * @param {Vector} pos Vehicle world position vector updated in-place on boundary hit.
     * @param {Float} forwardSpeed Current longitudinal speed in m/s.
     * @param {Float} lateralVelocity Current lateral velocity in m/s.
     * @returns {{ hitWall:Bool, speedMult:Float, latMult:Float }} Contact outcome and velocity multipliers.
     */
    public function enforceBoundaries(pos:Vec3, forwardSpeed:Float, lateralVelocity:Float):{ hitWall:Bool, speedMult:Float, latMult:Float };

    /**
     * Registers static physical foundation or boundary colliders in an Oimo world.
     *
     * @param {oimo.dynamics.World} world Target physics simulation world.
     * @returns {Void}
     */
    public function registerPhysicsColliders(world:oimo.dynamics.World):Void;

    /**
     * Removes previously registered static rigid bodies from an Oimo world.
     *
     * @param {oimo.dynamics.World} world Target physics simulation world.
     * @returns {Void}
     */
    public function unregisterPhysicsColliders(world:oimo.dynamics.World):Void;
}
