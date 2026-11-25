{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables #-}
-- | Core types: the 'X' monad, layouts, configuration and runtime state.
--
-- As in xmonad, the layout class lives here because layouts run in 'X'.
module Rivermonad.Core
  ( -- * Basic types
    Window, WorkspaceId, ScreenId (..), ScreenDetail (..), WindowSet, WindowSpace
  , Rectangle (..)
  , WindowInfo (..), OutputInfo (..), SeatInfo (..), Drag (..), DragKind (..)
  , Globals (..), Input (..), IPCAction (..), WindowCriteria (..), RestartNow (..)
    -- * Layouts
  , LayoutClass (..), Layout (..), readsLayout
  , Message, SomeMessage (..), fromMessage
    -- * Extensible state
  , ExtensionClass (..), StateExtension (..)
    -- * Configuration
  , XConfig (..), Default (..)
  , InputConfig (..), KeyboardConfig (..), PointerConfig (..), AccelProfile (..)
  , InputDev (..), XkbKb (..), LiDev (..), KeymapState (..)
  , ShadowConfig (..), Shadow (..)
  , AnimationConfig (..), Anim (..)
  , EffectsConfig (..)
    -- * The X monad
  , X, XConf (..), XState (..), RationalRectS, runX, io, catchX, userCode, userCodeDef
  , withWindowSet, gets, modify, asks, ask, get, put
    -- * Queries / ManageHook
  , Query (..), ManageHook, runQuery, liftX
    -- * Helpers
  , screenRect, emptyWindowInfo, All (..)
  ) where

import Control.Concurrent.Chan (Chan)
import qualified Control.Exception as E
import Control.Monad.Reader
import Control.Monad.State.Strict
import qualified Data.ByteString as B
import qualified Data.Map.Strict as M
import Data.Word (Word32)
import Data.Monoid (All (..), Endo (..))
import qualified Data.Set as S
import Data.Typeable (Typeable, cast)
import System.Exit (ExitCode)
import System.IO (hPutStrLn, stderr)

import Rivermonad.Keysym
import qualified Rivermonad.StackSet as W
import Rivermonad.StackSet (StackSet, Stack (..))
import Rivermonad.Wayland.Protocol (Event)
import Rivermonad.Wayland.Wire (Conn, ObjectId)

-- | A window is identified by its river_window_v1 object.
type Window = ObjectId
type WorkspaceId = String

newtype ScreenId = S Int
  deriving (Eq, Ord, Show, Read, Enum, Num, Integral, Real)

data Rectangle = Rectangle
  { rect_x      :: !Int
  , rect_y      :: !Int
  , rect_width  :: !Int
  , rect_height :: !Int
  } deriving (Show, Read, Eq, Ord)

data ScreenDetail = SD
  { sdOutput :: !ObjectId   -- ^ the river_output_v1 behind this screen
  , sdRect   :: !Rectangle  -- ^ area available to windows (bars excluded)
  } deriving (Eq, Show)

type WindowSet = StackSet WorkspaceId (Layout Window) Window ScreenId ScreenDetail
type WindowSpace = W.Workspace WorkspaceId (Layout Window) Window

screenRect :: ScreenDetail -> Rectangle
screenRect = sdRect

------------------------------------------------------------------------------
-- Messages and layouts

class Typeable a => Message a

data SomeMessage = forall a. Message a => SomeMessage a

fromMessage :: Message m => SomeMessage -> Maybe m
fromMessage (SomeMessage m) = cast m

-- | The layout class, as in xmonad. Implement 'pureLayout' / 'pureMessage'
-- for simple layouts, or 'doLayout' / 'handleMessage' when you need 'X'.
class Show (layout a) => LayoutClass layout a where
  -- | Lay out a whole workspace. Rarely overridden.
  runLayout :: W.Workspace WorkspaceId (layout a) a -> Rectangle -> X ([(a, Rectangle)], Maybe (layout a))
  runLayout (W.Workspace _ l ms) r = maybe (emptyLayout l r) (doLayout l r) ms

  doLayout :: layout a -> Rectangle -> Stack a -> X ([(a, Rectangle)], Maybe (layout a))
  doLayout l r s = pure (pureLayout l r s, Nothing)

  pureLayout :: layout a -> Rectangle -> Stack a -> [(a, Rectangle)]
  pureLayout _ r s = [(W.focus s, r)]

  emptyLayout :: layout a -> Rectangle -> X ([(a, Rectangle)], Maybe (layout a))
  emptyLayout _ _ = pure ([], Nothing)

  -- | React to a message. 'Nothing' means the layout did not change.
  handleMessage :: layout a -> SomeMessage -> X (Maybe (layout a))
  handleMessage l = pure . pureMessage l

  pureMessage :: layout a -> SomeMessage -> Maybe (layout a)
  pureMessage _ _ = Nothing

  -- | Human readable name, used by 'JumpToLayout' and status bars.
  description :: layout a -> String
  description = takeWhile (/= ' ') . show

-- | A layout of unknown type. 'Read' is required so layouts survive restarts.
data Layout a = forall l. (LayoutClass l a, Read (l a)) => Layout (l a)

instance Show (Layout a) where
  show (Layout l) = show l

instance LayoutClass Layout a where
  runLayout (W.Workspace i (Layout l) ms) r = fmap (fmap Layout) <$> runLayout (W.Workspace i l ms) r
  doLayout (Layout l) r s = fmap (fmap Layout) <$> doLayout l r s
  emptyLayout (Layout l) r = fmap (fmap Layout) <$> emptyLayout l r
  handleMessage (Layout l) m = fmap Layout <$> handleMessage l m
  description (Layout l) = description l

-- | Parse a layout using another layout of the same type as a template.
readsLayout :: Layout a -> String -> [(Layout a, String)]
readsLayout (Layout l) s = [ (Layout (x `asTypeOf` l), rest) | (x, rest) <- reads s ]

------------------------------------------------------------------------------
-- Extensible state (see Rivermonad.Util.ExtensibleState)

class Typeable a => ExtensionClass a where
  initialValue :: a
  -- | Use 'PersistentExtension' to keep the value across restarts.
  extensionType :: a -> StateExtension
  extensionType = StateExtension

data StateExtension
  = forall a. ExtensionClass a => StateExtension a
  | forall a. (Read a, Show a, ExtensionClass a) => PersistentExtension a

------------------------------------------------------------------------------
-- Per-window state

-- | Everything we know about a window from the compositor.
data WindowInfo = WindowInfo
  { wiNode       :: !ObjectId
  , wiAppId      :: !String
  , wiTitle      :: !String
  , wiIdentifier :: !String
  , wiParent     :: !(Maybe Window)
  , wiMinSize    :: !(Int, Int)
  , wiMaxSize    :: !(Int, Int)        -- ^ 0 = no preference
  , wiDims       :: !(Maybe (Int, Int)) -- ^ actual size reported by the compositor
  , wiDecoration :: !Word
  , wiManaged    :: !Bool               -- ^ already went through the manage hook
  , wiProposed   :: !(Maybe (Int, Int)) -- ^ last proposed size, to avoid resending
  , wiTiled      :: !(Maybe Word)       -- ^ last set_tiled edges sent
  , wiFullscreen :: !(Maybe ObjectId)   -- ^ output it is currently fullscreen on
  , wiDecoSent   :: !(Maybe Bool)       -- ^ last use_ssd (True) / use_csd (False) sent
  , wiGeom       :: !(Maybe Rectangle)  -- ^ last placement, borders included
  , wiAsync      :: !Bool               -- ^ the window prefers tearing (async presentation)
  , wiPid        :: !(Maybe Int)        -- ^ pid of the process that made it (unreliable: may be reused)
  , wiFxSent     :: !(Maybe (Word32, Int, Word32, Bool)) -- ^ last opacity, corner radius, blur and shadow sent (river-fx)
  } deriving (Show)

emptyWindowInfo :: ObjectId -> WindowInfo
emptyWindowInfo node = WindowInfo
  { wiNode = node, wiAppId = "", wiTitle = "", wiIdentifier = "", wiParent = Nothing
  , wiMinSize = (0, 0), wiMaxSize = (0, 0), wiDims = Nothing, wiDecoration = 3
  , wiManaged = False, wiProposed = Nothing, wiTiled = Nothing, wiFullscreen = Nothing
  , wiDecoSent = Nothing, wiGeom = Nothing, wiAsync = False, wiPid = Nothing, wiFxSent = Nothing }

data OutputInfo = OutputInfo
  { oiPos        :: !(Maybe (Int, Int))
  , oiDims       :: !(Maybe (Int, Int))
  , oiUsable     :: !(Maybe Rectangle)  -- ^ from river_layer_shell_output_v1
  , oiLayerShell :: !(Maybe ObjectId)
  , oiWlOutput   :: !(Maybe (ObjectId, Word32)) -- ^ bound wl_output and its version
  , oiName       :: !(Maybe String)             -- ^ connector name, e.g. "DP-1"
  , oiAsync      :: !Bool                       -- ^ async (tearing) presentation requested from river
  } deriving (Show)

data DragKind = DragMove | DragResize deriving (Show, Eq)

data Drag = Drag
  { dragKind   :: !DragKind
  , dragWindow :: !Window
  , dragStart  :: !Rectangle   -- ^ absolute geometry when the drag started
  , dragDelta  :: !(Int, Int)
  , dragSeat   :: !ObjectId
  } deriving (Show)

data SeatInfo = SeatInfo
  { siBindings      :: ![ObjectId]          -- ^ xkb and pointer binding objects
  , siEnabled       :: !Bool                -- ^ bindings enabled already
  , siPointerWindow :: !(Maybe Window)
  , siPointerPos    :: !(Maybe (Int, Int))
  , siPosAtLayout   :: !(Maybe (Int, Int))  -- ^ pointer position at the last layout change
  , siFocused       :: !(Maybe (Maybe Window)) -- ^ last focus request sent (Nothing = unknown)
  , siLayerSeat     :: !(Maybe ObjectId)
  , siLayerFocus    :: !Bool                -- ^ a layer surface (launcher, bar) has focus
  } deriving (Show)

data Globals = Globals
  { gRegistry   :: !ObjectId
  , gWm         :: !ObjectId
  , gWmVersion  :: !Int
  , gXkb        :: !ObjectId
  , gLayerShell :: !(Maybe ObjectId)
  , gInputManager :: !(Maybe ObjectId)  -- ^ river_input_manager_v1
  , gXkbConfig    :: !(Maybe ObjectId)  -- ^ river_xkb_config_v1
  , gLibinput     :: !(Maybe ObjectId)  -- ^ river_libinput_config_v1
  , gCompositor   :: !(Maybe ObjectId)  -- ^ wl_compositor (surfaces for decorations)
  , gShm          :: !(Maybe ObjectId)  -- ^ wl_shm (their buffers)
  , gFx         :: !(Maybe ObjectId)  -- ^ river_fx_v1: only on river-fx (river drawn with SceneFX)
  , gFxVersion  :: !Int               -- ^ version of river_fx_v1 bound (2: shadows, close fade)
  }

-- | Thrown to unwind the main loop so the new binary can be exec'd.
data RestartNow = RestartNow deriving (Show)
instance E.Exception RestartNow

-- | Requests arriving on the IPC socket (see "Rivermonad.IPC").
data IPCAction
  = IPCFocusWorkspace WorkspaceId     -- ^ like 'W.view': may move focus to another screen
  | IPCGreedyViewWorkspace WorkspaceId -- ^ like 'W.greedyView': bring it to this screen
  | IPCNextLayout
  | IPCJumpToLayout String
  | IPCFocusUp
  | IPCFocusDown
  | IPCRestart
  | IPCNextKeyboardLayout
  | IPCLogout                         -- ^ close every window, then end the session
  | IPCLogoutCheck Int                -- ^ internal: the graceful logout timed out
  | IPCNextWorkspace                  -- ^ the next / previous configured workspace
  | IPCPrevWorkspace
  | IPCToggleWorkspace                -- ^ back to the previous one
  | IPCMoveToWorkspace WorkspaceId    -- ^ the focused window
  | IPCClose                          -- ^ the focused window
  | IPCToggleFloating
  | IPCToggleFullscreen
  | IPCFocusMaster
  | IPCSwapMaster
  | IPCShrink
  | IPCExpand
  | IPCIncMaster Int
  | IPCFocusWindow WindowCriteria     -- ^ the next matching window (cycles on repeat)
  | IPCCloseWindow WindowCriteria     -- ^ every matching window
  | IPCMoveWindow WindowCriteria WorkspaceId  -- ^ every matching window
  | IPCSpawn String                   -- ^ run a shell command
  | IPCRun String                     -- ^ an action of 'ipcActions'
  deriving (Show, Eq)

-- | Which windows an IPC request is about: every field given must match.
data WindowCriteria = WindowCriteria
  { wcAppId :: !(Maybe String)   -- ^ the app id, exactly
  , wcTitle :: !(Maybe String)   -- ^ a part of the title
  , wcId    :: !(Maybe String)   -- ^ river's identifier, as in the @"Windows"@ reply
  } deriving (Show, Eq)

-- | Things the main loop reacts to.
data Input
  = InEvents [Event]
  | InAction IPCAction
  | InDisconnected String
  | InRestart     -- ^ restart the window manager (SIGUSR1 or after recompiling)
  | InQuit        -- ^ SIGTERM / SIGINT
  | InRun (X ())  -- ^ an action from another thread (a menu's answer, say),
                  --   run in the next manage sequence

------------------------------------------------------------------------------
-- Configuration

class Default a where
  def :: a

data XConfig = XConfig
  { terminal           :: !String
  , modMask            :: !KeyMask
  , borderWidth        :: !Int
  , normalBorderColor  :: !String              -- ^ "#rrggbb" or "#rrggbbaa"
  , focusedBorderColor :: !String
  , workspaces         :: ![WorkspaceId]
  , layoutHook         :: !(Layout Window)
  , manageHook         :: !ManageHook
  , handleEventHook    :: !(Event -> X All)   -- ^ return @All False@ to skip default handling
  , keys               :: !(XConfig -> M.Map (KeyMask, KeySym) (X ()))
  , mouseBindings      :: !(XConfig -> M.Map (KeyMask, Button) (Window -> X ()))
  , startupHook        :: !(X ())
  , logHook            :: !(X ())
  , focusFollowsMouse  :: !Bool
  , xcursorTheme       :: !(Maybe (String, Int))
  , allowTearing       :: !Bool  -- ^ let fullscreen windows that ask for it (games) tear for lower latency
  , input              :: !InputConfig  -- ^ keyboard layout, key repeat, touchpad and mouse
  , shadows            :: !(Maybe ShadowConfig)  -- ^ drop shadows under windows; Nothing = none
  , effects            :: !(Maybe EffectsConfig)
    -- ^ rounded corners and translucent windows; they need river-fx and
    -- are ignored on plain river. Nothing = none
  , animations         :: !(Maybe AnimationConfig)
    -- ^ windows slide to their place instead of jumping; Nothing = none
  , ipcActions         :: ![(String, X ())]
    -- ^ actions scripts can run by name over IPC (@{"Action":{"Run":"name"}}@);
    -- 'Rivermonad.Util.NamedActions.addDescrKeysP' adds every described key
  }

------------------------------------------------------------------------------
-- Effects

-- | Effects drawn by the compositor, through the river-fx-v1 protocol.
-- Only river-fx (river with SceneFX) has it; on plain river these settings
-- do nothing.
data EffectsConfig = EffectsConfig
  { fxCornerRadius    :: !Int     -- ^ rounded corners of windows, in pixels (0 = square)
  , fxActiveOpacity   :: !Double  -- ^ opacity of the focused window, 0..1
  , fxInactiveOpacity :: !Double  -- ^ opacity of the other windows, 0..1
  , fxBlur            :: !Double
    -- ^ blur what shows through windows, 0 (none) to 1. It costs GPU time:
    -- leave it at 0 if no window is translucent
  }

instance Default EffectsConfig where
  def = EffectsConfig 10 1 1 0

------------------------------------------------------------------------------
-- Animations

-- | Windows slide to their new place when the layout changes, and
-- workspaces slide in and out sideways. On plain river only positions are
-- animated; on river-fx windows also fade. A window takes its new size at
-- once: the protocol has no scaling.
data AnimationConfig = AnimationConfig
  { animDuration   :: !Int   -- ^ milliseconds a movement takes
  , animFps        :: !Int   -- ^ frames per second while something moves
  , animWorkspaces :: !Bool  -- ^ changing workspace slides the old one out and the new one in
  , animOpen       :: !Int   -- ^ a new window rises this many pixels into place (0 = it just appears)
  , animFade       :: !Bool
    -- ^ windows fade in when they appear and out when they close, and
    -- workspaces fade as they slide. Needs river-fx (opacity); on plain
    -- river nothing fades
  }

instance Default AnimationConfig where
  def = AnimationConfig 200 60 True 0 True

-- | A window moving from one position to another.
data Anim = Anim
  { anFrom    :: !(Int, Int)
  , anTo      :: !(Int, Int)
  , anStart   :: !Double             -- ^ monotonic seconds
  , anStarted :: !Bool               -- ^ its first frame was drawn: until then the clock waits
  , anLeaving :: !Bool               -- ^ its workspace is sliding out: hidden when it arrives
  , anClip    :: !(Maybe Rectangle)  -- ^ kept inside this screen while it moves
  , anFade    :: !Int                -- ^ 1 fades in as it goes, -1 fades out, 0 neither
  }

------------------------------------------------------------------------------
-- Input devices

-- | Keyboard, touchpad and mouse settings. 'Nothing' (or an empty string)
-- leaves the device or system default.
data InputConfig = InputConfig
  { keyboard :: !KeyboardConfig
  , touchpad :: !PointerConfig   -- ^ devices with tap-to-click support
  , mouse    :: !PointerConfig   -- ^ other pointers
  }

instance Default InputConfig where
  def = InputConfig def def def

-- | xkb names, as in @/etc/default/keyboard@ or sway's @xkb_*@ settings.
-- Several layouts are comma-separated (@"us,es"@); switch between them
-- with an option such as @"grp:alt_shift_toggle"@ or with
-- 'Rivermonad.Operations.nextKeyboardLayout'.
data KeyboardConfig = KeyboardConfig
  { kbLayout  :: !String
  , kbVariant :: !String               -- ^ per layout, comma-separated (@",mac"@)
  , kbOptions :: !String               -- ^ e.g. @"caps:escape,compose:ralt"@
  , kbModel   :: !String
  , kbRepeat  :: !(Maybe (Int, Int))   -- ^ (keys per second, delay in ms)
  , kbNumlock :: !(Maybe Bool)         -- ^ Num Lock state when a keyboard appears
  }

instance Default KeyboardConfig where
  def = KeyboardConfig "" "" "" "" Nothing Nothing

data AccelProfile = AccelFlat | AccelAdaptive
  deriving (Eq, Show)

data PointerConfig = PointerConfig
  { tapToClick         :: !(Maybe Bool)
  , naturalScroll      :: !(Maybe Bool)
  , disableWhileTyping :: !(Maybe Bool)
  , leftHanded         :: !(Maybe Bool)
  , middleEmulation    :: !(Maybe Bool)
  , accelProfile       :: !(Maybe AccelProfile)
  , accelSpeed         :: !(Maybe Double)    -- ^ -1 (slowest) .. 1 (fastest); 0 = device default
  }

instance Default PointerConfig where
  def = PointerConfig Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- | A river_input_device_v1 and what river told us about it.
data InputDev = InputDev
  { idType       :: !(Maybe Word32)   -- ^ keyboard 0, pointer 1, touch 2, tablet 3
  , idName       :: !String
  , idConfigured :: !Bool
  }

-- | A river_xkb_keyboard_v1.
data XkbKb = XkbKb
  { xkLayout    :: !(Int, String)     -- ^ current layout (index, name)
  , xkKeymapSet :: !Bool
  , xkNumlockSet :: !Bool
  }

-- | A river_libinput_device_v1: what it supports, collected until @done@.
data LiDev = LiDev
  { ldTapFingers    :: !Int
  , ldNatural       :: !Bool
  , ldDwt           :: !Bool
  , ldLeftHanded    :: !Bool
  , ldMiddle        :: !Bool
  , ldAccelProfiles :: !Word32
  , ldApplied       :: !Bool
  }

data KeymapState
  = NoKeymap                  -- ^ nothing configured: river's default keymap
  | KeymapPending ObjectId
  | KeymapReady ObjectId
  | KeymapFailed

------------------------------------------------------------------------------
-- Shadows

-- | Drop shadows. On plain river rivermonad draws them itself, as river
-- decorations below windows; on river-fx the compositor draws them, and
-- they follow the rounded corners of 'effects'.
data ShadowConfig = ShadowConfig
  { shadowRadius  :: !Int          -- ^ blur radius in pixels
  , shadowOffset  :: !(Int, Int)   -- ^ (x, y); (0, 4) puts the light above
  , shadowColor   :: !String       -- ^ "#rrggbb"
  , shadowOpacity :: !Double       -- ^ 0..1 at the window's edge
  , shadowTiled   :: !Bool         -- ^ also under tiled windows (off: they
                                   --   would darken their neighbours)
  }

instance Default ShadowConfig where
  def = ShadowConfig 18 (0, 5) "#000000" 0.5 False

-- | A window's shadow: a wl_surface with the river_decoration_v1 role.
data Shadow = Shadow
  { shSurface    :: !ObjectId
  , shDecoration :: !ObjectId
  , shDrawn      :: !(Maybe (Int, Int))  -- ^ box size it was drawn for
  , shBuffer     :: !(Maybe ObjectId)
  }

------------------------------------------------------------------------------
-- The X monad

data XConf = XConf
  { config  :: !XConfig
  , conn    :: !Conn
  , globals :: !Globals
  , inputs  :: !(Chan Input)
  , ipcPublish :: !(B.ByteString -> IO ()) -- ^ send a state line to IPC subscribers
  , ipcPublishWindows :: !(B.ByteString -> IO ()) -- ^ the reply to the IPC request "Windows"
  }

data XState = XState
  { windowset       :: !WindowSet
  , windowInfo      :: !(M.Map Window WindowInfo)
  , outputs         :: !(M.Map ObjectId OutputInfo)
  , seats           :: !(M.Map ObjectId SeatInfo)
  , keyActions      :: !(M.Map ObjectId (X ()))
  , pointerActions  :: !(M.Map ObjectId (ObjectId, Window -> X ())) -- ^ binding -> (seat, action)
  , pending         :: ![X ()]          -- ^ actions for the next manage sequence (newest first)
  , newWindows      :: ![Window]        -- ^ windows awaiting the manage hook (newest first)
  , outputsDirty    :: !Bool
  , haveScreens     :: !Bool
  , fullscreen      :: !(S.Set Window)
  , needsCenter     :: !(S.Set Window)  -- ^ floats to center once their size is known
  , shownWindows    :: !(S.Set Window)  -- ^ on screen after the last layout (not hidden by it)
  , anims           :: !(M.Map Window Anim)        -- ^ windows on their way somewhere
  , shownPos        :: !(M.Map Window (Int, Int))  -- ^ where each shown window was last drawn
  , shownTags       :: !(M.Map ObjectId WorkspaceId) -- ^ the workspace last shown on each output
  , animTick        :: !Bool                       -- ^ the next animation frame is already scheduled
  , drag            :: !(Maybe Drag)
  , sessionLocked   :: !Bool
  , started         :: !Bool            -- ^ startup hook already ran
  , restoreState    :: !(M.Map String (WorkspaceId, Maybe RationalRectS))
  , restarting      :: !Bool
  , restoreView     :: !(Maybe WorkspaceId) -- ^ workspace to show after a restart
  , restoreOrder    :: !(M.Map String (Int, Bool)) -- ^ identifier -> (stack position, focused)
  , borderWidths    :: !(M.Map Window Int)  -- ^ per-window border overrides set by layouts
  , extensibleState :: !(M.Map String (Either String StateExtension))
  , registryGlobals :: !(M.Map Word32 (B.ByteString, Word32)) -- ^ name -> (interface, version)
  , loggingOut      :: !(Maybe Int)     -- ^ a graceful logout is waiting for windows to close (attempt number)
  , layerDefault    :: !(Maybe ObjectId) -- ^ output last made river's default for layer surfaces
  , inputDevices    :: !(M.Map ObjectId InputDev)
  , xkbKeyboards    :: !(M.Map ObjectId XkbKb)
  , libinputDevices :: !(M.Map ObjectId LiDev)
  , keymapState     :: !KeymapState
  , shadowMap       :: !(M.Map Window Shadow)
  , retiredBuffers  :: !(S.Set ObjectId)  -- ^ replaced shadow buffers, destroyed on release
  }

-- | Serializable float geometry used by the restart state file.
type RationalRectS = (Rational, Rational, Rational, Rational)

newtype X a = X (ReaderT XConf (StateT XState IO) a)
  deriving (Functor, Applicative, Monad, MonadIO, MonadState XState, MonadReader XConf)

instance Semigroup a => Semigroup (X a) where
  a <> b = (<>) <$> a <*> b

instance Monoid a => Monoid (X a) where
  mempty = pure mempty

runX :: XConf -> XState -> X a -> IO (a, XState)
runX c st (X m) = runStateT (runReaderT m c) st

io :: MonadIO m => IO a -> m a
io = liftIO

-- | Run an action, falling back to another one (and discarding state
-- changes) if it throws. 'ExitCode' and restart exceptions are re-thrown.
catchX :: X a -> X a -> X a
catchX job errcase = do
  st <- get
  c <- ask
  (a, s') <- io $ runX c st job `E.catch` \(e :: E.SomeException) ->
    case (E.fromException e, E.fromException e) of
      (Just (_ :: ExitCode), _) -> E.throwIO e
      (_, Just RestartNow) -> E.throwIO e
      _ -> do
        hPutStrLn stderr ("rivermonad: user code raised: " ++ show e)
        runX c st errcase
  put s'
  pure a

userCode :: X a -> X (Maybe a)
userCode a = catchX (Just <$> a) (pure Nothing)

userCodeDef :: a -> X a -> X a
userCodeDef d a = maybe d id <$> userCode a

withWindowSet :: (WindowSet -> X a) -> X a
withWindowSet f = gets windowset >>= f

------------------------------------------------------------------------------
-- Queries

-- | A computation that inspects a window, used by manage hooks.
newtype Query a = Query (ReaderT Window X a)
  deriving (Functor, Applicative, Monad, MonadReader Window, MonadIO)

instance Semigroup a => Semigroup (Query a) where
  a <> b = (<>) <$> a <*> b

instance Monoid a => Monoid (Query a) where
  mempty = pure mempty

type ManageHook = Query (Endo WindowSet)

runQuery :: Query a -> Window -> X a
runQuery (Query m) = runReaderT m

liftX :: X a -> Query a
liftX = Query . lift
