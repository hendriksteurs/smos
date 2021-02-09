{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}

module Smos.Draw.Report
  ( drawReportCursor,
  )
where

import Brick.Types as B
import Brick.Widgets.Core as B
import Cursor.Brick
import Cursor.List.NonEmpty (foldNonEmptyCursor)
import Cursor.Simple.List.NonEmpty
import Data.Time
import Path
import Smos.Actions
import Smos.Cursor.Report.Entry
import Smos.Cursor.Report.Work
import Smos.Data
import Smos.Draw.Base
import Smos.Report.Filter
import Smos.Report.Formatting
import Smos.Report.Stuck
import Smos.Report.Work
import Smos.Style
import Smos.Types
import Text.Printf

drawReportCursor :: Select -> ReportCursor -> Drawer
drawReportCursor s = \case
  ReportNextActions narc -> drawNextActionReportCursor s narc
  ReportWaiting wrc -> drawWaitingReportCursor s wrc
  ReportTimestamps tsrc -> drawTimestampsReportCursor s tsrc
  ReportStuck src -> drawStuckReportCursor s src
  ReportWork wrc -> drawWorkReportCursor s wrc

drawNextActionReportCursor :: Select -> NextActionReportCursor -> Drawer
drawNextActionReportCursor s NextActionReportCursor {..} = do
  ercw <- drawEntryReportCursorSimple drawNextActionEntryCursor s nextActionReportCursorEntryReportCursor
  pure $ withHeading (str "Next Action Report") $ padAll 1 ercw

drawNextActionEntryCursor :: Select -> EntryReportEntryCursor (TodoState, UTCTime) -> Drawer' [Widget ResourceName]
drawNextActionEntryCursor s EntryReportEntryCursor {..} =
  pure $
    let sel =
          ( case s of
              MaybeSelected -> forceAttr selectedAttr . visible
              NotSelected -> id
          )
        (ts, _) = entryReportEntryCursorVal
     in [ drawFilePath entryReportEntryCursorFilePath,
          drawTodoState ts,
          sel $ drawHeader $ entryHeader $ forestCursorCurrent entryReportEntryCursorForestCursor
        ]

drawWaitingReportCursor :: Select -> WaitingReportCursor -> Drawer
drawWaitingReportCursor s WaitingReportCursor {..} = do
  ercw <- drawEntryReportCursorSimple drawWaitingEntryCursor s waitingReportCursorEntryReportCursor
  pure $ withHeading (str "Waiting Report") $ padAll 1 ercw

drawWaitingEntryCursor :: Select -> EntryReportEntryCursor UTCTime -> Drawer' [Widget ResourceName]
drawWaitingEntryCursor s EntryReportEntryCursor {..} = do
  now <- asks zonedTimeToUTC
  let sel =
        ( case s of
            MaybeSelected -> forceAttr selectedAttr . visible
            NotSelected -> id
        )
  pure
    [ str $ fromRelFile entryReportEntryCursorFilePath,
      sel $ drawHeader $ entryHeader $ forestCursorCurrent entryReportEntryCursorForestCursor,
      daysSinceWidget 7 now entryReportEntryCursorVal
    ]

daysSinceWidget :: Word -> UTCTime -> UTCTime -> Widget n
daysSinceWidget threshold now t = withAttr style $ str $ show i <> " days"
  where
    th1 = fromIntegral threshold :: Int
    th2 = floor ((fromIntegral threshold :: Double) / 3 * 2) :: Int
    th3 = floor ((fromIntegral threshold :: Double) / 3) :: Int
    style
      | i >= th1 = waitingReportLongWait
      | i >= th2 = waitingReportMidWait
      | i >= th3 = waitingReportShortWait
      | otherwise = waitingReportNoWait
    i = daysSince now t

drawEntryReportCursorSimple ::
  (Select -> EntryReportEntryCursor a -> Drawer' [Widget ResourceName]) -> Select -> EntryReportCursor a -> Drawer
drawEntryReportCursorSimple go = drawEntryReportCursor $ \s mnec ->
  case mnec of
    Nothing -> pure $ txtWrap "Empty report"
    Just wecs -> verticalNonEmptyCursorTableM (go NotSelected) (go s) (go NotSelected) wecs

drawEntryReportCursor :: (Select -> Maybe (NonEmptyCursor (EntryReportEntryCursor a)) -> Drawer) -> Select -> EntryReportCursor a -> Drawer
drawEntryReportCursor func s EntryReportCursor {..} = do
  tableW <-
    func
      ( case entryReportCursorSelection of
          EntryReportFilterSelected -> NotSelected
          EntryReportSelected -> s
      )
      entryReportCursorSelectedEntryReportEntryCursors
  pure $
    vBox
      [ viewport ResourceViewport Vertical tableW,
        ( case entryReportCursorSelection of
            EntryReportFilterSelected -> withAttr selectedAttr
            EntryReportSelected -> id
        )
          $ let ms =
                  case entryReportCursorSelection of
                    EntryReportFilterSelected -> s
                    EntryReportSelected -> NotSelected
             in hBox [textLineWidget "Filter:", txt " ", drawTextCursor ms entryReportCursorFilterBar]
      ]

drawTimestampsReportCursor :: Select -> TimestampsReportCursor -> Drawer
drawTimestampsReportCursor s TimestampsReportCursor {..} = do
  tsrw <-
    drawEntryReportCursor
      ( \s' mnec ->
          case mnec of
            Nothing -> pure $ txtWrap "Empty timestamps report"
            Just tsecs -> do
              now <- ask
              ws <- mapM (drawTimestampReportLine s') $ makeTimestampReportLines now tsecs
              pure $ tableWidget ws
      )
      s
      timestampsReportCursorEntryReportCursor
  pure $
    withHeading (str "Agenda Report: Today") $ padAll 1 tsrw

data TimestampsReportLine
  = ReportSelectedEntryLine !(EntryReportEntryCursor TimestampsEntryCursor)
  | ReportEntryLine !(EntryReportEntryCursor TimestampsEntryCursor)
  | ReportNowLine !LocalTime
  | ReportHourLine !Int

makeTimestampReportLines :: ZonedTime -> NonEmptyCursor (EntryReportEntryCursor TimestampsEntryCursor) -> [TimestampsReportLine]
makeTimestampReportLines now = foldNonEmptyCursor $ \befores current afters ->
  insertReportNowLine now $ insertReportHourLines now $ concat [map ReportEntryLine befores, [ReportSelectedEntryLine current], map ReportEntryLine afters]

drawTimestampReportLine :: Select -> TimestampsReportLine -> Drawer' [Widget ResourceName]
drawTimestampReportLine s = \case
  ReportSelectedEntryLine tsec -> drawTimestampsEntryCursor s tsec
  ReportEntryLine tsec -> drawTimestampsEntryCursor NotSelected tsec
  ReportNowLine now ->
    pure $
      map
        (withAttr agendaReportNowLineAttr)
        [ str $ formatTime defaultTimeLocale "%H:%M:%S" now,
          str "--------",
          str "---",
          str "---",
          str "------------",
          str "---"
        ]
  ReportHourLine i ->
    pure
      [ str (printf "%02d:00   " i),
        empty,
        empty,
        empty,
        empty,
        empty
      ]
  where
    empty = str " "

insertReportHourLines :: ZonedTime -> [TimestampsReportLine] -> [TimestampsReportLine]
insertReportHourLines now = go [8 .. 18]
  where
    ZonedTime lt _ = now
    today = localDay lt
    go hs [] = map ReportHourLine hs
    go [] es = es
    go (h : hs) (e : es) =
      let alt = timestampsReportLineLocalTime now e
          hlt = hourLineLocalTime today h
       in if alt < hlt
            then e : go (h : hs) es
            else ReportHourLine h : go hs (e : es)

timestampsReportLineLocalTime :: ZonedTime -> TimestampsReportLine -> LocalTime
timestampsReportLineLocalTime now = \case
  ReportSelectedEntryLine tec -> timestampLocalTime $ timestampsEntryCursorTimestamp $ entryReportEntryCursorVal tec
  ReportEntryLine tec -> timestampLocalTime $ timestampsEntryCursorTimestamp $ entryReportEntryCursorVal tec
  ReportNowLine lt -> lt
  ReportHourLine h -> hourLineLocalTime (localDay $ zonedTimeToLocalTime now) h

hourLineLocalTime :: Day -> Int -> LocalTime
hourLineLocalTime d h = LocalTime d (TimeOfDay h 0 0)

insertReportNowLine :: ZonedTime -> [TimestampsReportLine] -> [TimestampsReportLine]
insertReportNowLine now = go
  where
    nowL = ReportNowLine $ zonedTimeToLocalTime now
    go = \case
      [] -> [nowL]
      (x : xs) ->
        if isBefore now x
          then nowL : x : xs
          else x : go xs

isBefore :: ZonedTime -> TimestampsReportLine -> Bool
isBefore now after =
  let afterLT = timestampsReportLineLocalTime now after
      nowUTC = zonedTimeToUTC now
   in nowUTC <= localTimeToUTC (zonedTimeZone now) afterLT

drawTimestampsEntryCursor :: Select -> EntryReportEntryCursor TimestampsEntryCursor -> Drawer' [Widget ResourceName]
drawTimestampsEntryCursor s EntryReportEntryCursor {..} = do
  let sel =
        ( case s of
            MaybeSelected -> forceAttr selectedAttr . visible
            NotSelected -> id
        )
      e = forestCursorCurrent entryReportEntryCursorForestCursor
  let TimestampsEntryCursor {..} = entryReportEntryCursorVal
  tsw <- drawTimestampPrettyRelative timestampsEntryCursorTimestamp
  let lt = timestampLocalTime timestampsEntryCursorTimestamp
  pure
    [ str $ formatTime defaultTimeLocale "%H:%M" lt,
      withAttr agendaReportRelativeAttr tsw,
      drawTimestampName timestampsEntryCursorTimestampName,
      maybe (str " ") drawTodoState $ entryState e,
      sel $ drawHeader $ entryHeader e,
      str $ fromRelFile entryReportEntryCursorFilePath
    ]

drawStuckReportCursor :: Select -> StuckReportCursor -> Drawer
drawStuckReportCursor s StuckReportCursor {..} = do
  sprw <- case stuckReportCursorNonEmptyCursor of
    Nothing -> pure $ str "Empty stuck projects report"
    Just wecs -> verticalNonEmptyCursorTableM (drawStuckReportEntry NotSelected) (drawStuckReportEntry s) (drawStuckReportEntry NotSelected) wecs
  pure $ withHeading (str "Stuck Projects Report") $ padAll 1 sprw

drawStuckReportEntry :: Select -> StuckReportEntry -> Drawer' [Widget ResourceName]
drawStuckReportEntry s StuckReportEntry {..} = do
  now <- asks zonedTimeToUTC
  let sel =
        ( case s of
            MaybeSelected -> forceAttr selectedAttr . visible
            NotSelected -> id
        )

  pure
    [ str $ fromRelFile stuckReportEntryFilePath,
      maybe (str " ") drawTodoState stuckReportEntryState,
      sel $ drawHeader stuckReportEntryHeader,
      maybe
        (str " ")
        (\ts -> if ts > now then str "future" else daysSinceWidget 21 now ts)
        stuckReportEntryLatestChange
    ]

drawWorkReportCursor :: Select -> WorkReportCursor -> Drawer
drawWorkReportCursor s WorkReportCursor {..} = pure $ str $ show workReportCursorResultEntries
