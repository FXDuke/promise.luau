-- Made and maintained by FXDuke
-- TypeDef
type LoadedData = {
	thumbnail: string,
	name: string,	
	userId: number,
};

type Template = {
	mugshot: ImageLabel,
	name: TextLabel,
	button: ImageButton	
};

type FriendInfo = {
	Username: string,
	Id: number,
	DisplayName: string,
	IsOnline: boolean
};

-- Generic
local Players = game:GetService("Players");
local UserInputService = game:GetService("UserInputService");
local SocialService = game:GetService("SocialService");
local Player = Players.LocalPlayer;
local Promise = require(script:WaitForChild("promise"));
local TweenService = game:GetService("TweenService");

-- Constants 
local ContentSize = 6; -- Amount of templates in content frame
local FriendList: {[number]: FriendInfo} = {};
local Mobile = (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled);
local InviteText = "Invite your friends for 5% boost! (+10% for every friend who joins!)";

	-- Thumnail info
local thumbnailType = Enum.ThumbnailType.HeadShot;
local thumbnailSize = Mobile and Enum.ThumbnailSize.Size48x48 or Enum.ThumbnailSize.Size60x60;

	-- Convert unsorted list to indexable array
local friendListUnsorted = Players:GetFriendsAsync(Player.UserId);
while true do 
	for index, value in friendListUnsorted:GetCurrentPage() do 
		FriendList[#FriendList+1] = value;
	end
	if (friendListUnsorted.IsFinished) then break end;
	friendListUnsorted:AdvanceToNextPageAsync();
end

-- Data
local preloadedData: {[number]: {LoadedData}} = {};
local contentFrameTemplates: {[number]: Template} = {};
local linkedContentFrameIds: {[number]: number} = {};
local currentPage = 1;
local RenderPagePromise;
local InviteOptions = Instance.new("ExperienceInviteOptions");

	-- Invite Options
InviteOptions.PromptMessage = InviteText;
InviteOptions.LaunchData = tostring(Player.UserId);

-- Assets 
local Template = script:WaitForChild("template");
local Parent = script.Parent;

	-- Parent
local Holder = Parent:WaitForChild("holder");

		-- Holder
local Background = Holder:WaitForChild("background");

			-- Background
local PageNavigationFrame = Background:WaitForChild("pageNavigation");
local ContentFrame = Background:WaitForChild("content");
local FindPlayerInput = Background:WaitForChild("findPlayer");

				-- Page Navigation
local RightButton = PageNavigationFrame:WaitForChild("Right");
local LeftButton = PageNavigationFrame:WaitForChild("Left");
local PageLabel = PageNavigationFrame:WaitForChild("pageLabel");

				-- Create Content Frames
					-- Tweens
local HoverTweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine);
local HoverLeaveTweenInfo = TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.Out);
local ClickTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Sine);
local ClickReleaseTweenInfo = TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out);

local OriginSize = Template.InviteButton.Size;
local OriginPosition = Template.InviteButton.Position;
local HoverScale = 1.1;
local ClickScale = 0.8;

local function scaleUDim2(UIDimension2: UDim2, Scalar: number): UDim2
	return UDim2.new(UIDimension2.X.Scale*Scalar, 0, UIDimension2.Y.Scale*Scalar, 0);
end
local function findDifference(UIDimension2: UDim2, UIDimension2_2: UDim2): UDim2
	return UDim2.new((UIDimension2.X.Scale-UIDimension2_2.X.Scale)*0.5, 0, (UIDimension2.Y.Scale-UIDimension2_2.Y.Scale)*0.5, 0);
end
					-- Creation
local function OnClick(ImageButton: ImageButton, id: number)
	ImageButton.MouseEnter:Connect(function()
		TweenService:Create(ImageButton, HoverTweenInfo, {Size = scaleUDim2(OriginSize, HoverScale), Position = OriginPosition + findDifference(OriginSize, scaleUDim2(OriginSize, HoverScale))}):Play();
	end)
	ImageButton.MouseLeave:Connect(function()
		TweenService:Create(ImageButton, HoverLeaveTweenInfo, {Size = OriginSize, Position = OriginPosition}):Play();
	end)
	ImageButton.MouseButton1Down:Connect(function()
		TweenService:Create(ImageButton, ClickTweenInfo, {Size = scaleUDim2(OriginSize, ClickScale), Position = OriginPosition + findDifference(OriginSize, scaleUDim2(OriginSize, ClickScale))}):Play();
	end)
	ImageButton.MouseButton1Up:Connect(function()
		TweenService:Create(ImageButton, ClickReleaseTweenInfo, {Size = OriginSize, Position = OriginPosition}):Play();
		local targetId = linkedContentFrameIds[id];
		if (targetId < 0) then return end;
		local success, name = pcall(function()
			return Players:GetNameFromUserIdAsync(targetId) and SocialService:CanSendGameInviteAsync(Player, linkedContentFrameIds[targetId]);
		end);
		if (not success) then return end;
		InviteOptions.InviteUser = targetId;
		SocialService:PromptGameInvite(Player, InviteOptions);
	end)
end
				
for i = 1, ContentSize do 
	local clonedFrame: Frame = Template:Clone();
	clonedFrame.LayoutOrder = i;
	clonedFrame.Name = i;
	clonedFrame.Parent = ContentFrame;
	contentFrameTemplates[i] = clonedFrame;
	linkedContentFrameIds[i] = -1;
	OnClick(clonedFrame.InviteButton, i);
end

-- Functions 
	-- Rendering Data
local function RenderPage() -- Renders Page Content
	local PreloadedPageInfo = preloadedData[currentPage] :: {[number]: LoadedData};
	RenderPagePromise = nil
	if (not PreloadedPageInfo) then error("Friend page (" .. currentPage .. ") does not exist.") end;
	
	for index = 1, ContentSize do 
		local info = preloadedData[currentPage][index]	:: LoadedData;
		local LinkedTemplate = contentFrameTemplates[index] :: Template;
		LinkedTemplate.Visible = (info);
		if (not info) then continue end;

		LinkedTemplate.name.Text = info.name;
		LinkedTemplate.mugshot.Image = info.thumbnail;
		linkedContentFrameIds[index] = info.userId;
	end
	PageLabel.Text = "Page " .. currentPage;
end

	-- Loading Data
local function LoadPlayerData(_promise: Promise, PageNumber: number, Index: number) -- Loads player data individually
	local info = FriendList[Index];
	local thumbnail;
	task.spawn(function() thumbnail = Players:GetUserThumbnailAsync(info.Id, thumbnailType, thumbnailSize) end);
	repeat _promise:Yield() until thumbnail;
	preloadedData[PageNumber][Index % ContentSize + 1] = {
		thumbnail = thumbnail,
		userId = info.Id,
		name = info.DisplayName
	} :: LoadedData;
end
	
local function LoadPageData(_promise: Promise, PageNumber: number) -- Loads in page data
	local startIndex = ContentSize*(PageNumber-1) + 1;
	if (startIndex > #FriendList) then return end;
	preloadedData[PageNumber] = {};
	
	local remaining = 0;
	local function resolved() remaining-=1 end;
	for Index = startIndex, startIndex+(ContentSize-1) do 
		if (FriendList[Index] == nil) then break end;
		local promise = Promise.new(LoadPlayerData, PageNumber, Index);
		promise:Finally(resolved);
		remaining += 1;
	end
	
	repeat _promise:Yield() until remaining == 0;
end

local function PreLoadData(_promise: Promise?) -- Preloads all unloaded content
	local remaining = 0;
	local function resolved() remaining-=1 end;
	for Index = math.max(currentPage-1, 1), currentPage+1 do 
		if (preloadedData[Index]) then continue end;
		local promise = Promise.new(LoadPageData, Index);
		promise:Finally(resolved);
		remaining += 1;
	end
	
	if (not _promise) then return end;
	repeat _promise:Yield() until remaining == 0;
end

local function MovePage() -- Clears irrelevant memory and preloads content
	local Buffer = {} :: {[number]: {FriendInfo}};
	for Index = math.max(currentPage-1, 1), currentPage+1 do 
		if (not preloadedData[Index]) then continue end;
		Buffer[Index] = preloadedData[Index];
	end
	preloadedData = Buffer;
	
	local preLoaded = (preloadedData[currentPage]);
	RenderPagePromise = Promise.new();
	RenderPagePromise:Finally(RenderPage);
	if (preLoaded and #preloadedData[currentPage] > 0) then 
		RenderPagePromise:Resolve();
		PreLoadData();
		return;
	end
	RenderPagePromise:Attempt(PreLoadData);
end

	-- Events
local function RightNavigatorClicked()
	if (RenderPagePromise) then return end;
	if (currentPage * ContentSize + 1 > #FriendList) then return end;
	currentPage += 1;
	MovePage();
end

local function LeftNavigatorClicked()
	if (RenderPagePromise) then return end;
	if (currentPage-1 < 1) then return end;
	currentPage -= 1;
	MovePage();
end

local function InputAreaInputBegan()
	local input = FindPlayerInput.Text;
	if (#input == 0) then return end;
	-- Find Friend
	local _player: FriendInfo;
	for index, playerInfo: FriendInfo in FriendList do 
		if ((input:lower():sub(1, #input) == playerInfo.DisplayName:lower():sub(1, #input) or input:lower():sub(1, #input) == playerInfo.Username:lower():sub(1, #input) or tonumber(input) == playerInfo.Id) and playerInfo.Id ~= Player.UserId) then
			_player = playerInfo;
			break;
		end
	end
	-- Send Invite
	if (not _player) then return end;
	FindPlayerInput.Text = _player.DisplayName;
	local success, name = pcall(function()
		return Players:GetNameFromUserIdAsync(_player.Id) and SocialService:CanSendGameInviteAsync(Player, _player.Id);
	end);
	if (not success) then return end;
	InviteOptions.InviteUser = _player.Id;
	SocialService:PromptGameInvite(Player, InviteOptions);
end

-- Connections
RightButton.MouseButton1Up:Connect(RightNavigatorClicked);
LeftButton.MouseButton1Up:Connect(LeftNavigatorClicked);
FindPlayerInput.FocusLost:Connect(InputAreaInputBegan);

-- Init
MovePage();
