# phoenix-apple

## Installation

### Adding to an existing workspace

1. [Download the most recent tagged version of phoenix-apple](https://github.com/shareup-app/phoenix-apple/releases/tag/v1.0.0)
2. Add `Phoenix.xcodeproj` to your workspace (.xcworkspace file) by clicking on "Add Files to [your workspace]". Select `Phoenix.xcodeproj` and click "Add."
3. If you have not already done so, add a "Copy Frameworks" build phase to your app's target. Select your app's project file in Xcode's sidebar and then click on the "Build Phases" tab. Click the + button above "Target Dependencies" for your app's target. Choose "New Copy Files Phase". Rename the newly-created phase to "Copy Frameworks". Change the destination from "Resources" to "Frameworks".
4. To add the new library to your app, if you're not already there, select your app's project file in Xcode's sidebar. Click on the "Build Phases" tab and open the "Copy Frameworks" section. Drag the "Phoenix.framework" file from inside the Phoenix framework's "Products" group to the "Copy Frameworks" section. Then, drag the "Starscream.framework" file from inside the Starscream sub-project within the Phoenix project to the "Copy Frameworks" section. After doing this, you should see  "Phoenix.framework" and "Starscream.framework" show up in the sidebar under your app's frameworks group. Click on the framework, show the Utilities (the third pane on the right side in Xcode), and verify that the framework's location is "Relative to Build Products".

### Adding as a sub-project to an existing project
1. [Download the most recent tagged version of phoenix-apple](https://github.com/shareup-app/phoenix-apple/releases/tag/v1.0.0)
2. Drag the `Phoenix.xcodeproj` file from Finder to your existing project in Xcode's sidebar.
3. Select the existing project file in Xcode's sidebar and then click on the "Build Phases" tab. Click on the "+" inside of the "Link Binary With Libraries" section. Select "Phoenix.framework" in the screen that appears.
4. To add the new library to your app, if you're not already there, select your app's project file in Xcode's sidebar. Click on the "Build Phases" tab and open the "Copy Frameworks" section. Drag the "Phoenix.framework" file from inside the Phoenix framework's "Products" group to the "Copy Frameworks" section. Then, drag the "Starscream.framework" file from inside the Starscream sub-project within the Phoenix project to the "Copy Frameworks" section. After doing this, you should see  "Phoenix.framework" and "Starscream.framework" show up in the sidebar under your app's frameworks group. Click on the framework, show the Utilities (the third pane on the right side in Xcode), and verify that the framework's location is "Relative to Build Products".
