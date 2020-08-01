module Smos.Calendar.Import.RenderSpec
  ( spec,
  )
where

import Data.Maybe
import Smos.Calendar.Import.Event.Gen ()
import Smos.Calendar.Import.Render
import Test.Hspec
import Test.Validity

spec :: Spec
spec = do
  describe "renderEvent" $ do
    it "produces valid results" $ producesValidsOnValids renderEvent
