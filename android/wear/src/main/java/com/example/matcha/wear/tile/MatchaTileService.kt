package com.example.matcha.wear.tile

import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.ModifiersBuilders.Clickable
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders.Timeline
import androidx.wear.protolayout.material.Chip
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

private const val RESOURCES_VERSION = "1"

/**
 * A quick-glance Matcha tile. Shows the brand + a chip that opens the watch
 * app's live scores. (Rendering live scores directly in the tile is a future
 * refinement; the tile launches straight into them today.)
 */
class MatchaTileService : TileService() {

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> {
        val device = requestParams.deviceConfiguration
        val layout: LayoutElement = PrimaryLayout.Builder(device)
            .setPrimaryLabelTextContent(
                Text.Builder(this, "MATCHA")
                    .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                    .setColor(argb(0xFF8AB4F8.toInt()))
                    .build(),
            )
            .setContent(
                Text.Builder(this, "Live scores")
                    .setTypography(Typography.TYPOGRAPHY_TITLE3)
                    .setColor(argb(0xFFFFFFFF.toInt()))
                    .build(),
            )
            .setPrimaryChipContent(
                Chip.Builder(this, openAppClickable(), device)
                    .setPrimaryLabelContent("Open")
                    .build(),
            )
            .build()

        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setTileTimeline(Timeline.fromLayoutElement(layout))
            .setFreshnessIntervalMillis(15 * 60 * 1000L)
            .build()

        return Futures.immediateFuture(tile)
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> =
        Futures.immediateFuture(
            ResourceBuilders.Resources.Builder().setVersion(RESOURCES_VERSION).build(),
        )

    private fun openAppClickable(): Clickable =
        Clickable.Builder()
            .setId("open_matcha")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(
                        ActionBuilders.AndroidActivity.Builder()
                            .setPackageName(packageName)
                            .setClassName("com.example.matcha.wear.presentation.WearMainActivity")
                            .build(),
                    )
                    .build(),
            )
            .build()
}
