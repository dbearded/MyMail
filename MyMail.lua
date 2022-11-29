SLASH_MYMAIL1 = "/mm"
SLASH_MYMAIL2 = "/mymail"
SlashCmdList["MYMAIL"] = function(msg)
	ShowUIPanel(MyMailFrame)
end

SEND_MY_MAIL_TAB_LIST = {};
SEND_MY_MAIL_TAB_LIST[1] = "SendMyMailNameEditBox";
SEND_MY_MAIL_TAB_LIST[2] = "SendMyMailSubjectEditBox";
SEND_MY_MAIL_TAB_LIST[3] = "MyMailEditBox";
SEND_MY_MAIL_TAB_LIST[4] = "SendMyMailMoneyGold";
SEND_MY_MAIL_TAB_LIST[5] = "SendMyMailMoneyCopper";

function MyMailFrame_OnLoad(self)
	UIPanelWindows["MyMailFrame"] = {
        area = "left",
        pushable = 1,
        whileDead = 1,
    }
	-- Init pagenum
	MyInboxFrame.pageNum = 1;
	-- Tab Handling code
	self.maxTabWidth = self:GetWidth() / 3;
	PanelTemplates_SetNumTabs(self, 2);
	PanelTemplates_SetTab(self, 1);
	-- Register for events
	self:RegisterEvent("MAIL_SHOW");
	self:RegisterEvent("MAIL_INBOX_UPDATE");
	self:RegisterEvent("MAIL_CLOSED");
	self:RegisterEvent("MAIL_SEND_INFO_UPDATE");
	self:RegisterEvent("MAIL_SEND_SUCCESS");
	self:RegisterEvent("MAIL_FAILED");
	self:RegisterEvent("MAIL_SUCCESS");	
	self:RegisterEvent("CLOSE_INBOX_ITEM");
	self:RegisterEvent("MAIL_LOCK_SEND_ITEMS");
	self:RegisterEvent("MAIL_UNLOCK_SEND_ITEMS");
	self:RegisterEvent("TRIAL_STATUS_UPDATE");
	-- Set previous and next fields
	MoneyInputFrame_SetPreviousFocus(SendMyMailMoney, MyMailEditBox);
	MoneyInputFrame_SetNextFocus(SendMyMailMoney, SendMyMailNameEditBox);
	MoneyFrame_SetMaxDisplayWidth(SendMyMailMoneyFrame, 160);
	MyMailFrame_UpdateTrialState(self);
end

function MyMailFrame_UpdateTrialState(self)
	local isTrialOrVeteran = GameLimitedMode_IsActive();
	MyMailFrameTab2:SetShown(not isTrialOrVeteran);
	self.trialError:SetShown(isTrialOrVeteran);
end

function MyMailFrame_OnEvent(self, event, ...)
	if ( event == "MAIL_SHOW" ) then
		ShowUIPanel(MyMailFrame);
		if ( not MyMailFrame:IsShown() ) then
			CloseMail();
			return;
		end

		-- Update the roster so auto-completion works
		if ( IsInGuild() and GetNumGuildMembers() == 0 ) then
			C_GuildInfo.GuildRoster();
		end

		OpenAllBags(self);
		SendMyMailFrame_Update();
		MyMailFrameTab_OnClick(nil, 1);
		CheckInbox();
		DoEmote("READ", nil, true);
	elseif ( event == "MAIL_INBOX_UPDATE" ) then
		MyInboxFrame_Update();
		OpenMyMail_Update();
	elseif ( event == "MAIL_SEND_INFO_UPDATE" ) then
		SendMyMailFrame_Update();
	elseif ( event == "MAIL_SEND_SUCCESS" ) then
		SendMyMailFrame_Reset();
		PlaySound(SOUNDKIT.IG_ABILITY_PAGE_TURN);
		-- If open mail frame is open then switch the mail frame back to the inbox
		if ( SendMyMailFrame.sendMode == "reply" ) then
			MyMailFrameTab_OnClick(nil, 1);
		end
	elseif ( event == "MAIL_FAILED" ) then
		SendMyMailMailButton:Enable();
	elseif ( event == "MAIL_SUCCESS" ) then
		SendMyMailMailButton:Enable();
		if ( MyInboxNextPageButton:IsEnabled() ) then
			MyInboxGetMoreMail();
		end
	elseif ( event == "MAIL_CLOSED" ) then
		CancelEmote();
		HideUIPanel(MyMailFrame);
		CloseAllBags(self);
		SendMyMailFrameLockSendMyMail:Hide();
		StaticPopup_Hide("CONFIRM_MAIL_ITEM_UNREFUNDABLE");
	elseif ( event == "CLOSE_INBOX_ITEM" ) then
		local mailID = ...;
		if ( mailID == MyInboxFrame.OpenMyMailID ) then
			HideUIPanel(OpenMyMailFrame);
		end
	elseif ( event == "MAIL_LOCK_SEND_ITEMS" ) then
		local slotNum, itemLink = ...;
		SendMyMailFrameLockSendMyMail:Show();
		local itemName, itemLink, itemRarity, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture = GetItemInfo(itemLink);
		local r, g, b = GetItemQualityColor(itemRarity)
		StaticPopup_Show("CONFIRM_MAIL_ITEM_UNREFUNDABLE", nil, nil, {["texture"] = itemTexture, ["name"] = itemName, ["color"] = {r, g, b, 1}, ["link"] = itemLink, ["slot"] = slotNum});
	elseif ( event == "MAIL_UNLOCK_SEND_ITEMS") then
		SendMyMailFrameLockSendMyMail:Hide();
		StaticPopup_Hide("CONFIRM_MAIL_ITEM_UNREFUNDABLE");
	elseif ( event == "TRIAL_STATUS_UPDATE" ) then
		MyMailFrame_UpdateTrialState(self);
	end
end

function MyMailFrame_OnMouseWheel(self, value)
	if ( value > 0 ) then
		if ( MyInboxPrevPageButton:IsEnabled() ) then
			MyInboxPrevPage();
		end
	else
		if ( MyInboxNextPageButton:IsEnabled() ) then
			MyInboxNextPage();
		end	
	end
end

function MyMailFrameTab_OnClick(self, tabID)
	if ( not tabID ) then
		tabID = self:GetID();
	end
	PanelTemplates_SetTab(MyMailFrame, tabID);
	if ( tabID == 1 ) then
		-- Inbox tab clicked
		ButtonFrameTemplate_HideButtonBar(MyMailFrame)
		MyMailFrameInset:SetPoint("TOPLEFT", 4, -58);
		MyInboxFrame:Show();
		SendMyMailFrame:Hide();
		SetSendMailShowing(false);
	else
		-- SendMyMail tab clicked
		ButtonFrameTemplate_ShowButtonBar(MyMailFrame)
		MyMailFrameInset:SetPoint("TOPLEFT", 4, -80);
		MyInboxFrame:Hide();
		SendMyMailFrame:Show();
		SendMyMailFrame_Update();
		SetSendMailShowing(true);

		-- Set the send mode to dictate the flow after a mail is sent
		SendMyMailFrame.sendMode = "send";
	end
	PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
end

-- Inbox functions

function MyInboxFrame_Update()
	local numItems, totalItems = GetInboxNumItems();
	local index = ((MyInboxFrame.pageNum - 1) * INBOXITEMS_TO_DISPLAY) + 1;
	local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount, wasRead, x, y, z, isGM, firstItemQuantity;
	local icon, button, expireTime, senderText, subjectText, buttonIcon;
	
	if ( totalItems > numItems ) then
		if ( not MyInboxFrame.maxShownMails ) then
			MyInboxFrame.maxShownMails = numItems;
		end
		MyInboxFrame.overflowMails = totalItems - numItems;
		MyInboxFrame.shownMails = numItems;
	else
		MyInboxFrame.overflowMails = nil;
	end
	
	for i=1, INBOXITEMS_TO_DISPLAY do
		if ( index <= numItems ) then
			-- Setup mail item
			packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount, wasRead, x, y, z, isGM, firstItemQuantity, firstItemID = GetInboxHeaderInfo(index);
			
			-- Set icon
			if ( packageIcon ) and ( not isGM ) then
				icon = packageIcon;
			else
				icon = stationeryIcon;
			end

			
			-- If no sender set it to "Unknown"
			if ( not sender ) then
				sender = UNKNOWN;
			end
			button = _G["MyMailItem"..i.."Button"];
			button:Show();
			button.index = index;
			button.hasItem = itemCount;
			button.itemCount = itemCount;
			SetItemButtonCount(button, firstItemQuantity);
			if ( firstItemQuantity ) then
				SetItemButtonQuality(button, select(3, GetItemInfo(firstItemID)), firstItemID);
			else
				button.IconBorder:Hide();
				button.IconOverlay:Hide();
			end
			
			buttonIcon = _G["MyMailItem"..i.."ButtonIcon"];
			buttonIcon:SetTexture(icon);
			subjectText = _G["MyMailItem"..i.."Subject"];
			subjectText:SetText(subject);
			senderText = _G["MyMailItem"..i.."Sender"];
			senderText:SetText(sender);
			
			-- If hasn't been read color the button yellow
			if ( wasRead ) then
				senderText:SetTextColor(0.75, 0.75, 0.75);
				subjectText:SetTextColor(0.75, 0.75, 0.75);
				_G["MyMailItem"..i.."ButtonSlot"]:SetVertexColor(0.5, 0.5, 0.5);
				SetDesaturation(buttonIcon, true);
				button.IconBorder:SetVertexColor(0.5, 0.5, 0.5);
			else
				senderText:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);
				subjectText:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
				_G["MyMailItem"..i.."ButtonSlot"]:SetVertexColor(1.0, 0.82, 0);
				SetDesaturation(buttonIcon, false);
			end
			-- Format expiration time
			if ( daysLeft >= 1 ) then
				daysLeft = GREEN_FONT_COLOR_CODE..format(DAYS_ABBR, floor(daysLeft)).." "..FONT_COLOR_CODE_CLOSE;
			else
				daysLeft = RED_FONT_COLOR_CODE..SecondsToTime(floor(daysLeft * 24 * 60 * 60))..FONT_COLOR_CODE_CLOSE;
			end
			expireTime = _G["MyMailItem"..i.."ExpireTime"];
			expireTime:SetText(daysLeft);
			-- Set expiration time tooltip
			if ( InboxItemCanDelete(index) ) then
				expireTime.tooltip = TIME_UNTIL_DELETED;
			else
				expireTime.tooltip = TIME_UNTIL_RETURNED;
			end
			expireTime:Show();
			-- Is a C.O.D. package
			if ( CODAmount > 0 ) then
				_G["MyMailItem"..i.."ButtonCOD"]:Show();
				_G["MyMailItem"..i.."ButtonCODBackground"]:Show();
				button.cod = CODAmount;
			else
				_G["MyMailItem"..i.."ButtonCOD"]:Hide();
				_G["MyMailItem"..i.."ButtonCODBackground"]:Hide();
				button.cod = nil;
			end
			-- Contains money
			if ( money > 0 ) then
				button.money = money;
			else
				button.money = nil;
			end
			-- Set highlight
			if ( MyInboxFrame.OpenMyMailID == index ) then
				button:SetChecked(true);
				SetPortraitToTexture("OpenMyMailFrameIcon", stationeryIcon);
			else
				button:SetChecked(false);
			end
		else
			-- Clear everything
			_G["MyMailItem"..i.."Button"]:Hide();
			_G["MyMailItem"..i.."Sender"]:SetText("");
			_G["MyMailItem"..i.."Subject"]:SetText("");
			_G["MyMailItem"..i.."ExpireTime"]:Hide();
			MoneyInputFrame_ResetMoney(SendMyMailMoney);
		end
		index = index + 1;
	end

	-- Handle page arrows
	if ( MyInboxFrame.pageNum == 1 ) then
		MyInboxPrevPageButton:Disable();
	else
		MyInboxPrevPageButton:Enable();
	end
	if ( (MyInboxFrame.pageNum * INBOXITEMS_TO_DISPLAY) < numItems ) then
		MyInboxNextPageButton:Enable();
	else
		MyInboxNextPageButton:Disable();
	end
	if ( totalItems > numItems) then
		InboxTooMuchMail:Show();
	else
		InboxTooMuchMail:Hide();
	end
end

function MyInboxFrame_OnClick(self, index)
	if ( self:GetChecked() ) then
		MyInboxFrame.OpenMyMailID = index;
		OpenMyMailFrame.updateButtonPositions = true;
		OpenMyMail_Update();
		--OpenMyMailFrame:Show();
		ShowUIPanel(OpenMyMailFrame);
		OpenMyMailFrameInset:SetPoint("TOPLEFT", 4, -80);
		PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
	else
		MyInboxFrame.OpenMyMailID = 0;
		HideUIPanel(OpenMyMailFrame);		
	end
	MyInboxFrame_Update();
end

function MyInboxFrame_OnModifiedClick(self, index)
	local _, _, _, _, _, cod = GetInboxHeaderInfo(index);
	if ( cod <= 0 ) then
		AutoLootMyMailItem(index);
	end
	MyInboxFrame_OnClick(self, index);
end

function MyInboxFrameItem_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	if ( self.hasItem ) then
		if ( self.itemCount == 1) then
			local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = GameTooltip:SetInboxItem(self.index);
			if(speciesID and speciesID > 0) then
				BattlePetToolTip_Show(speciesID, level, breedQuality, maxHealth, power, speed, name);
			end
		else
			GameTooltip:AddLine(MAIL_MULTIPLE_ITEMS.." ("..self.itemCount..")");
		end
	end
	if (self.money) then
		if ( self.hasItem ) then
			GameTooltip:AddLine(" ");
		end
		GameTooltip:AddLine(ENCLOSED_MONEY, nil, nil, nil, true);
		SetTooltipMoney(GameTooltip, self.money);
		SetMoneyFrameColor("GameTooltipMoneyFrame1", "white");
	elseif (self.cod) then
		if ( self.hasItem ) then
			GameTooltip:AddLine(" ");
		end
		GameTooltip:AddLine(COD_AMOUNT, nil, nil, nil, true);
		SetTooltipMoney(GameTooltip, self.cod);
		if ( self.cod > GetMoney() ) then
			SetMoneyFrameColor("GameTooltipMoneyFrame1", "red");
		else
			SetMoneyFrameColor("GameTooltipMoneyFrame1", "white");
		end
	end
	GameTooltip:Show();
end

function MyInboxNextPage()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	MyInboxFrame.pageNum = MyInboxFrame.pageNum + 1;
	MyInboxGetMoreMail();	
	MyInboxFrame_Update();
end

function MyInboxPrevPage()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
	MyInboxFrame.pageNum = MyInboxFrame.pageNum - 1;
	MyInboxGetMoreMail();	
	MyInboxFrame_Update();
end

function MyInboxGetMoreMail()
	-- get more mails if there is an overflow and less than max are being shown
	if ( MyInboxFrame.overflowMails and MyInboxFrame.shownMails < MyInboxFrame.maxShownMails ) then
		CheckInbox();
	end
end

-- Open Mail functions

function OpenMyMailFrame_OnHide()
	StaticPopup_Hide("DELETE_MAIL");
	if ( not MyInboxFrame.OpenMyMailID ) then
		MyInboxFrame_Update();
		PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE);
		return;
	end

	-- Determine if this is an auction temp invoice
	local isInvoice = select(5, GetInboxText(MyInboxFrame.OpenMyMailID));
	local isAuctionTempInvoice = false;
	if ( isInvoice ) then
		local invoiceType, itemName, playerName, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin = GetInboxInvoiceInfo(MyInboxFrame.OpenMyMailID);
		if (invoiceType == "seller_temp_invoice") then
			isAuctionTempInvoice = true;
		end
	end
	
	-- If mail contains no items, then delete it on close
	local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount, wasRead, wasReturned, textCreated  = GetInboxHeaderInfo(MyInboxFrame.OpenMyMailID);
	if ( money == 0 and not itemCount and textCreated and not isAuctionTempInvoice ) then
		DeleteInboxItem(MyInboxFrame.OpenMyMailID);
	end
	MyInboxFrame.OpenMyMailID = 0;
	MyInboxFrame_Update();
	PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE);
end

function OpenMyMailFrame_UpdateButtonPositions(letterIsTakeable, textCreated, stationeryIcon, money)
	if ( OpenMyMailFrame.activeAttachmentButtons ) then
		while (#OpenMyMailFrame.activeAttachmentButtons > 0) do
			tremove(OpenMyMailFrame.activeAttachmentButtons);
		end
	else
		OpenMyMailFrame.activeAttachmentButtons = {};
	end
	if ( OpenMyMailFrame.activeAttachmentRowPositions ) then
		while (#OpenMyMailFrame.activeAttachmentRowPositions  > 0) do
			tremove(OpenMyMailFrame.activeAttachmentRowPositions );
		end
	else
		OpenMyMailFrame.activeAttachmentRowPositions = {};
	end

	local rowAttachmentCount = 0;

	-- letter
	if ( letterIsTakeable and not textCreated ) then
		SetItemButtonTexture(OpenMyMailLetterButton, stationeryIcon);
		tinsert(OpenMyMailFrame.activeAttachmentButtons, OpenMyMailLetterButton);
		rowAttachmentCount = rowAttachmentCount + 1;
	else
		SetItemButtonTexture(OpenMyMailLetterButton, "");
	end
	-- money
	if ( money == 0 ) then
		SetItemButtonTexture(OpenMyMailMoneyButton, "");
	else
		SetItemButtonTexture(OpenMyMailMoneyButton, GetCoinIcon(money));
		tinsert(OpenMyMailFrame.activeAttachmentButtons, OpenMyMailMoneyButton);
		rowAttachmentCount = rowAttachmentCount + 1;
	end
	-- items
	for i=1, ATTACHMENTS_MAX_RECEIVE do
		local attachmentButton = OpenMyMailFrame.OpenMyMailAttachments[i];
		if HasInboxItem(MyInboxFrame.OpenMyMailID, i) then
			tinsert(OpenMyMailFrame.activeAttachmentButtons, attachmentButton);
			rowAttachmentCount = rowAttachmentCount + 1;

			local name, itemID, itemTexture, count, quality, canUse = GetInboxItem(MyInboxFrame.OpenMyMailID, i);
			if name then
				attachmentButton.name = name;
				SetItemButtonTexture(attachmentButton, itemTexture);
				SetItemButtonCount(attachmentButton, count);
				SetItemButtonQuality(attachmentButton, quality, itemID);
			else
				attachmentButton.name = nil;
				SetItemButtonTexture(attachmentButton, "Interface/Icons/INV_Misc_QuestionMark");
				SetItemButtonCount(attachmentButton, 0);
				SetItemButtonQuality(attachmentButton, nil);
			end

			if canUse then
				SetItemButtonTextureVertexColor(attachmentButton, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
			else
				SetItemButtonTextureVertexColor(attachmentButton, 1.0, 0.1, 0.1);
			end
		else
			attachmentButton:Hide();
		end

		if ( rowAttachmentCount >= ATTACHMENTS_PER_ROW_RECEIVE ) then
			tinsert(OpenMyMailFrame.activeAttachmentRowPositions, {cursorxstart=0,cursorxend=ATTACHMENTS_PER_ROW_RECEIVE - 1});
			rowAttachmentCount = 0;
		end
	end
	-- insert last row's position data
	if ( rowAttachmentCount > 0 ) then
		local xstart = (ATTACHMENTS_PER_ROW_RECEIVE - rowAttachmentCount) / 2;
		local xend = xstart + rowAttachmentCount - 1;
		tinsert(OpenMyMailFrame.activeAttachmentRowPositions, {cursorxstart=xstart,cursorxend=xend});
	end

	-- hide unusable attachment buttons
	for i=ATTACHMENTS_MAX_RECEIVE + 1, ATTACHMENTS_MAX do
		_G["OpenMyMailAttachmentButton"..i]:Hide();
	end
end

function OpenMyMail_Update()
	if ( not MyInboxFrame.OpenMyMailID ) then
		return;
	end
	if ( CanComplainInboxItem(MyInboxFrame.OpenMyMailID) ) then
		OpenMyMailReportSpamButton:Enable();
		OpenMyMailReportSpamButton:Show();
		OpenMyMailSender:SetPoint("BOTTOMRIGHT", OpenMyMailReportSpamButton, "BOTTOMLEFT" , -5, 0);
	else
		OpenMyMailReportSpamButton:Hide();
		OpenMyMailSender:SetPoint("BOTTOMRIGHT", OpenMyMailFrame, "TOPRIGHT" , -12, -54);
	end

	-- Setup mail item
	local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, itemCount, wasRead, wasReturned, textCreated, canReply = GetInboxHeaderInfo(MyInboxFrame.OpenMyMailID);
	-- Set sender and subject
	if ( not sender or not canReply or sender == UnitName("player") ) then
		OpenMyMailReplyButton:Disable();
	else
		OpenMyMailReplyButton:Enable();
	end
	if ( not sender ) then
		sender = UNKNOWN;
	end
	-- Save sender name to pass to a potential spam report
	MyInboxFrame.OpenMyMailSender = sender;
	OpenMyMailSender.Name:SetText(sender);
	OpenMyMailSubject:SetText(subject);
	-- Set Text
	local bodyText, stationeryID1, stationeryID2, isTakeable, isInvoice = GetInboxText(MyInboxFrame.OpenMyMailID);
	OpenMyMailBodyText:SetText(bodyText, true);
	if ( stationeryID1 and stationeryID2 ) then
		OpenStationeryBackgroundLeft:SetTexture(stationeryID1);
		OpenStationeryBackgroundRight:SetTexture(stationeryID2);
	end

	-- Is an invoice
	if ( isInvoice ) then
		local invoiceType, itemName, playerName, bid, buyout, deposit, consignment, moneyDelay, etaHour, etaMin, count, commerceAuction = GetInboxInvoiceInfo(MyInboxFrame.OpenMyMailID);
		if ( playerName ) then
			-- Setup based on whether player is the buyer or the seller
			local buyMode;
			if ( count and count > 1 ) then
				itemName = format(AUCTION_MAIL_ITEM_STACK, itemName, count);
			end
			OpenMyMailInvoicePurchaser:SetShown(not commerceAuction);
			OpenMyMailInvoiceBuyMode:SetShown(not commerceAuction);
			if ( invoiceType == "buyer" ) then
				if ( bid == buyout ) then
					buyMode = "("..BUYOUT..")";
				else
					buyMode = "("..HIGH_BIDDER..")";
				end
				OpenMyMailInvoiceItemLabel:SetText(ITEM_PURCHASED_COLON.." "..itemName.."  "..buyMode);
				OpenMyMailInvoicePurchaser:SetText(SOLD_BY_COLON.." "..playerName);
				OpenMyMailInvoiceAmountReceived:SetText(AMOUNT_PAID_COLON);
				-- Clear buymode
				OpenMyMailInvoiceBuyMode:SetText("");
				-- Position amount paid
				OpenMyMailInvoiceAmountReceived:SetPoint("TOPRIGHT", "OpenMyMailInvoiceSalePrice", "TOPRIGHT", 0, 0);
				-- Update purchase price
				MoneyFrame_Update("OpenMyMailTransactionAmountMoneyFrame", bid);	
				-- Position buy line
				OpenMyMailArithmeticLine:SetPoint("TOP", "OpenMyMailInvoicePurchaser", "BOTTOMLEFT", 125, 0);
				-- Not used for a purchase invoice
				OpenMyMailInvoiceSalePrice:Hide();
				OpenMyMailInvoiceDeposit:Hide();
				OpenMyMailInvoiceHouseCut:Hide();
				OpenMyMailDepositMoneyFrame:Hide();
				OpenMyMailHouseCutMoneyFrame:Hide();
				OpenMyMailSalePriceMoneyFrame:Hide();
				OpenMyMailInvoiceNotYetSent:Hide();
				OpenMyMailInvoiceMoneyDelay:Hide();
			elseif (invoiceType == "seller") then
				OpenMyMailInvoiceItemLabel:SetText(ITEM_SOLD_COLON.." "..itemName);
				OpenMyMailInvoicePurchaser:SetText(PURCHASED_BY_COLON.." "..playerName);
				OpenMyMailInvoiceAmountReceived:SetText(AMOUNT_RECEIVED_COLON);
				-- Determine if auction was bought out or bid on
				if ( bid == buyout ) then
					OpenMyMailInvoiceBuyMode:SetText("("..BUYOUT..")");
				else
					OpenMyMailInvoiceBuyMode:SetText("("..HIGH_BIDDER..")");
				end
				-- Position amount received
				OpenMyMailInvoiceAmountReceived:SetPoint("TOPRIGHT", "OpenMyMailInvoiceHouseCut", "BOTTOMRIGHT", 0, -18);
				-- Position buy line
				OpenMyMailArithmeticLine:SetPoint("TOP", "OpenMyMailInvoiceHouseCut", "BOTTOMRIGHT", 0, 9);
				MoneyFrame_Update("OpenMyMailSalePriceMoneyFrame", bid);
				MoneyFrame_Update("OpenMyMailDepositMoneyFrame", deposit);
				MoneyFrame_Update("OpenMyMailHouseCutMoneyFrame", consignment);
				SetMoneyFrameColor("OpenMyMailHouseCutMoneyFrame", "red");
				MoneyFrame_Update("OpenMyMailTransactionAmountMoneyFrame", bid+deposit-consignment);

				-- Show these guys if the player was the seller
				OpenMyMailInvoiceSalePrice:Show();
				OpenMyMailInvoiceDeposit:Show();
				OpenMyMailInvoiceHouseCut:Show();
				OpenMyMailDepositMoneyFrame:Show();
				OpenMyMailHouseCutMoneyFrame:Show();
				OpenMyMailSalePriceMoneyFrame:Show();
				OpenMyMailInvoiceNotYetSent:Hide();
				OpenMyMailInvoiceMoneyDelay:Hide();
			elseif (invoiceType == "seller_temp_invoice") then
				if ( bid == buyout ) then
					buyMode = "("..BUYOUT..")";
				else
					buyMode = "("..HIGH_BIDDER..")";
				end
				OpenMyMailInvoiceItemLabel:SetText(ITEM_SOLD_COLON.." "..itemName.."  "..buyMode);
				OpenMyMailInvoicePurchaser:SetText(PURCHASED_BY_COLON.." "..playerName);
				OpenMyMailInvoiceAmountReceived:SetText(AUCTION_INVOICE_PENDING_FUNDS_COLON);
				-- Clear buymode
				OpenMyMailInvoiceBuyMode:SetText("");
				-- Position amount paid
				OpenMyMailInvoiceAmountReceived:SetPoint("TOPRIGHT", "OpenMyMailInvoiceSalePrice", "TOPRIGHT", 0, 0);
				-- Update purchase price
				MoneyFrame_Update("OpenMyMailTransactionAmountMoneyFrame", bid+deposit-consignment);	
				-- Position buy line
				OpenMyMailArithmeticLine:SetPoint("TOP", "OpenMyMailInvoicePurchaser", "BOTTOMLEFT", 125, 0);
				-- How long they have to wait to get the money
				OpenMyMailInvoiceMoneyDelay:SetFormattedText(AUCTION_INVOICE_FUNDS_DELAY, "12:22");
				-- Not used for a temp sale invoice
				OpenMyMailInvoiceSalePrice:Hide();
				OpenMyMailInvoiceDeposit:Hide();
				OpenMyMailInvoiceHouseCut:Hide();
				OpenMyMailDepositMoneyFrame:Hide();
				OpenMyMailHouseCutMoneyFrame:Hide();
				OpenMyMailSalePriceMoneyFrame:Hide();
				OpenMyMailInvoiceNotYetSent:Show();
				OpenMyMailInvoiceMoneyDelay:Show();
			end
			OpenMyMailInvoiceFrame:Show();
		end
	else
		OpenMyMailInvoiceFrame:Hide();
	end

	local itemButtonCount, itemRowCount = OpenMyMail_GetItemCounts(isTakeable, textCreated, money);
	if ( OpenMyMailFrame.updateButtonPositions ) then
		OpenMyMailFrame_UpdateButtonPositions(isTakeable, textCreated, stationeryIcon, money);
	end
	if ( OpenMyMailFrame.activeAttachmentRowPositions ) then
		itemRowCount = #OpenMyMailFrame.activeAttachmentRowPositions;
	end

	-- record the original number of buttons that the mail needs
	OpenMyMailFrame.itemButtonCount = itemButtonCount;

	-- Determine starting position for buttons
	local marginxl = 10 + 4;
	local marginxr = 43 + 4;
	local areax = OpenMyMailFrame:GetWidth() - marginxl - marginxr;
	local iconx = OpenMyMailAttachmentButton1:GetWidth() + 2;
	local icony = OpenMyMailAttachmentButton1:GetHeight() + 2;
	local gapx1 = floor((areax - (iconx * ATTACHMENTS_PER_ROW_RECEIVE)) / (ATTACHMENTS_PER_ROW_RECEIVE - 1));
	local gapx2 = floor((areax - (iconx * ATTACHMENTS_PER_ROW_RECEIVE) - (gapx1 * (ATTACHMENTS_PER_ROW_RECEIVE - 1))) / 2);
	local gapy1 = 3;
	local gapy2 = 3;
	local areay = gapy2 + OpenMyMailAttachmentText:GetHeight() + gapy2 + (icony * itemRowCount) + (gapy1 * (itemRowCount - 1)) + gapy2;
	local indentx = marginxl + gapx2;
	local indenty = 28 + gapy2;
	local tabx = (iconx + gapx1) + 6; --this magic number changes the button spacing
	local taby = (icony + gapy1);
	local scrollHeight = 305 - areay;
	if (scrollHeight > 256) then
		scrollHeight = 256;
		areay = 305 - scrollHeight;
	end

	-- Resize the scroll frame
	OpenMyMailScrollFrame:SetHeight(scrollHeight);
	OpenMyMailScrollChildFrame:SetHeight(scrollHeight);
	OpenMyMailHorizontalBarLeft:SetPoint("TOPLEFT", "OpenMyMailFrame", "BOTTOMLEFT", 2, 39 + areay);
	OpenScrollBarBackgroundTop:SetHeight(min(scrollHeight, 256));
	OpenScrollBarBackgroundTop:SetTexCoord(0, 0.484375, 0, min(scrollHeight, 256) / 256);
	OpenStationeryBackgroundLeft:SetHeight(scrollHeight);
	OpenStationeryBackgroundLeft:SetTexCoord(0, 1.0, 0, min(scrollHeight, 256) / 256);
	OpenStationeryBackgroundRight:SetHeight(scrollHeight);
	OpenStationeryBackgroundRight:SetTexCoord(0, 1.0, 0, min(scrollHeight, 256) / 256);

	-- Set attachment text
	if ( itemButtonCount > 0 ) then
		OpenMyMailAttachmentText:SetText(TAKE_ATTACHMENTS);
		OpenMyMailAttachmentText:SetTextColor(HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b);
		OpenMyMailAttachmentText:SetPoint("TOPLEFT", "OpenMyMailFrame", "BOTTOMLEFT", indentx, indenty + (icony * itemRowCount) + (gapy1 * (itemRowCount - 1)) + gapy2 + OpenMyMailAttachmentText:GetHeight());
	else
		OpenMyMailAttachmentText:SetText(NO_ATTACHMENTS);
		OpenMyMailAttachmentText:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b);
		OpenMyMailAttachmentText:SetPoint("TOPLEFT", "OpenMyMailFrame", "BOTTOMLEFT", marginxl + (areax - OpenMyMailAttachmentText:GetWidth()) / 2, indenty + (areay - OpenMyMailAttachmentText:GetHeight()) / 2 + OpenMyMailAttachmentText:GetHeight());
	end
	-- Set letter
	if ( isTakeable and not textCreated ) then
		OpenMyMailLetterButton:Show();
	else
		OpenMyMailLetterButton:Hide();
	end
	-- Set Money
	if ( money == 0 ) then
		OpenMyMailMoneyButton:Hide();
		OpenMyMailFrame.money = nil;
	else
		OpenMyMailMoneyButton:Show();
		OpenMyMailFrame.money = money;
	end
	-- Set Items
	if ( itemRowCount > 0 and OpenMyMailFrame.activeAttachmentButtons ) then
		local firstAttachName;
		local rowIndex = 1;
		local cursorx = OpenMyMailFrame.activeAttachmentRowPositions[1].cursorxstart;
		local cursorxend = OpenMyMailFrame.activeAttachmentRowPositions[1].cursorxend;
		local cursory = itemRowCount - 1;
		for i, attachmentButton in ipairs(OpenMyMailFrame.activeAttachmentButtons) do
			attachmentButton:SetPoint("TOPLEFT", OpenMyMailFrame, "BOTTOMLEFT", indentx + (tabx * cursorx), indenty + icony + (taby * cursory));
			if attachmentButton ~= OpenMyMailLetterButton and attachmentButton ~= OpenMyMailMoneyButton then
				if cursory >= 0 and HasInboxItem(MyInboxFrame.OpenMyMailID, attachmentButton:GetID()) then
					if attachmentButton.name then
						if not firstAttachName then
							firstAttachName = attachmentButton.name;
						end
					end

					attachmentButton:Enable();
					attachmentButton:Show();
				else
					attachmentButton:Hide();
				end
			end

			cursorx = cursorx + 1;
			if (cursorx > cursorxend) then
				rowIndex = rowIndex + 1;

				cursory = cursory - 1;
				if ( rowIndex <= itemRowCount ) then
					cursorx = OpenMyMailFrame.activeAttachmentRowPositions[rowIndex].cursorxstart;
					cursorxend = OpenMyMailFrame.activeAttachmentRowPositions[rowIndex].cursorxend;
				end
			end
		end

		OpenMyMailFrame.itemName = firstAttachName;
	else
		OpenMyMailFrame.itemName = nil;
	end

	-- Set COD
	if ( CODAmount > 0 ) then
		OpenMyMailFrame.cod = CODAmount;
	else
		OpenMyMailFrame.cod = nil;
	end
	-- Set button to delete or return to sender
	if ( InboxItemCanDelete(MyInboxFrame.OpenMyMailID) ) then
		OpenMyMailDeleteButton:SetText(DELETE);
	else
		OpenMyMailDeleteButton:SetText(MAIL_RETURN);
	end
end

function OpenMyMail_GetItemCounts(letterIsTakeable, textCreated, money)
	local itemButtonCount = 0;
	local itemRowCount = 0;
	local numRows = 0;
	if ( letterIsTakeable and not textCreated ) then
		itemButtonCount = itemButtonCount + 1;
		itemRowCount = itemRowCount + 1;
	end
	if ( money ~= 0 ) then
		itemButtonCount = itemButtonCount + 1;
		itemRowCount = itemRowCount + 1;
	end
	for i=1, ATTACHMENTS_MAX_RECEIVE do
		if HasInboxItem(MyInboxFrame.OpenMyMailID, i) then
			itemButtonCount = itemButtonCount + 1;
			itemRowCount = itemRowCount + 1;
		end

		if ( itemRowCount >= ATTACHMENTS_PER_ROW_RECEIVE ) then
			numRows = numRows + 1;
			itemRowCount = 0;
		end
	end
	if ( itemRowCount > 0 ) then
		numRows = numRows + 1;
	end
	return itemButtonCount, numRows;
end

function OpenMyMail_Reply()
	MyMailFrameTab_OnClick(nil, 2);
	SendMyMailNameEditBox:SetText(OpenMyMailSender.Name:GetText())
	local subject = OpenMyMailSubject:GetText();
	local prefix = MAIL_REPLY_PREFIX.." ";
	if ( strsub(subject, 1, strlen(prefix)) ~= prefix ) then
		subject = prefix..subject;
	end
	SendMyMailSubjectEditBox:SetText(subject)
	MyMailEditBox:GetEditBox():SetFocus();

	-- Set the send mode so the work flow can change accordingly
	SendMyMailFrame.sendMode = "reply";
end

function OpenMyMail_Delete()
	if ( InboxItemCanDelete(MyInboxFrame.OpenMyMailID) ) then
		if ( OpenMyMailFrame.itemName ) then
			StaticPopup_Show("DELETE_MAIL", OpenMyMailFrame.itemName);
			return;
		elseif ( OpenMyMailFrame.money ) then
			StaticPopup_Show("DELETE_MONEY");
			return;
		else
			DeleteInboxItem(MyInboxFrame.OpenMyMailID);
		end
	else
		ReturnInboxItem(MyInboxFrame.OpenMyMailID);
		StaticPopup_Hide("COD_CONFIRMATION");
	end
	MyInboxFrame.OpenMyMailID = nil;
	HideUIPanel(OpenMyMailFrame);
end

function OpenMyMail_ReportSpam()
	local reportInfo = ReportInfo:CreateMailReportInfo(Enum.ReportType.Mail, MyInboxFrame.OpenMyMailID);
	if(reportInfo) then 
		ReportFrame:InitiateReport(reportInfo, MyInboxFrame.OpenMyMailSender); 
	end		
	OpenMyMailReportSpamButton:Disable();
end


function OpenMyMailAttachment_OnEnter(self, index)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = GameTooltip:SetInboxItem(MyInboxFrame.OpenMyMailID, index);
	if(speciesID and speciesID > 0) then
		BattlePetToolTip_Show(speciesID, level, breedQuality, maxHealth, power, speed, name);
	end

	if ( OpenMyMailFrame.cod ) then
		SetTooltipMoney(GameTooltip, OpenMyMailFrame.cod);
		if ( OpenMyMailFrame.cod > GetMoney() ) then
			SetMoneyFrameColor("GameTooltipMoneyFrame1", "red");
		else
			SetMoneyFrameColor("GameTooltipMoneyFrame1", "white");
		end
	end
	GameTooltip:Show();
end

function OpenMyMailAttachment_OnClick(self, index)
	if ( OpenMyMailFrame.cod and (OpenMyMailFrame.cod > GetMoney()) ) then
		StaticPopup_Show("COD_ALERT");
	elseif ( OpenMyMailFrame.cod ) then
		OpenMyMailFrame.lastTakeAttachment = index;
		StaticPopup_Show("COD_CONFIRMATION");
		OpenMyMailFrame.updateButtonPositions = false;
	else
		TakeInboxItem(MyInboxFrame.OpenMyMailID, index);
		OpenMyMailFrame.updateButtonPositions = false;
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
end

-- SendMyMail functions

function SendMyMailMailButton_OnClick(self)
	self:Disable();
	local copper = MoneyInputFrame_GetCopper(SendMyMailMoney);
	SetSendMyMailCOD(0);
	SetSendMyMailMoney(0);
	if ( SendMyMailSendMoneyButton:GetChecked() ) then
		-- Send Money
		if ( copper > 0 ) then
			-- Confirmation is now done through the secure transfer system
			SetSendMyMailMoney(copper)
		end
	else
		-- Send C.O.D.
		if ( copper > 0 ) then
			SetSendMyMailCOD(copper);
		end
	end
	SendMyMailFrame_SendMyMail();
end

function SendMyMailFrame_SendMyMail()
	SendMyMail(SendMyMailNameEditBox:GetText(), SendMyMailSubjectEditBox:GetText(), MyMailEditBox:GetInputText());
end

function SendMyMailFrame_EnableSendMyMailButton()
	SendMyMailMailButton:Enable();
end

function SendMyMailFrame_Update()
	-- Update the item(s) being sent
	local itemCount = 0;
	local itemTitle;
	local gap = false;
	local last = 0;
	for i=1, ATTACHMENTS_MAX_SEND do
		local SendMyMailAttachmentButton = SendMyMailFrame.SendMyMailAttachments[i];

		if HasSendMailItem(i) then
			itemCount = itemCount + 1;

			local itemName, itemID, itemTexture, stackCount, quality = GetSendMyMyMailItem(i);
			SendMyMailAttachmentButton:SetNormalTexture(itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark");
			SetItemButtonCount(SendMyMailAttachmentButton, stackCount or 0);
			SetItemButtonQuality(SendMyMailAttachmentButton, quality, itemID);
		
			-- determine what a name for the message in case it doesn't already have one
			if not itemTitle and itemName then
				if stackCount <= 1 then
					itemTitle = itemName;
				else
					itemTitle = itemName.." ("..stackCount..")";
				end
			end

			if last + 1 ~= i then
				gap = true;
			end
			last = i;
		else
			SendMyMailAttachmentButton:SetNormalTexture(nil);
			SetItemButtonCount(SendMyMailAttachmentButton, 0);
			SetItemButtonQuality(SendMyMailAttachmentButton, nil);
		end
	end

	-- Enable or disable C.O.D. depending on whether or not there's an item to send
	if ( itemCount > 0 ) then
		SendMyMailCODButton:Enable();
		SendMyMailCODButtonText:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b);

		if SendMyMailSubjectEditBox:GetText() == "" or SendMyMailSubjectEditBox:GetText() == SendMyMailFrame.previousItem then
			itemTitle = itemTitle or "";
			SendMyMailSubjectEditBox:SetText(itemTitle);
			SendMyMailFrame.previousItem = itemTitle;
		end
	else
		-- If no itemname see if the subject is the name of the previously held item, if so clear the subject
		if ( SendMyMailSubjectEditBox:GetText() == SendMyMailFrame.previousItem ) then
			SendMyMailSubjectEditBox:SetText("");	
		end
		SendMyMailFrame.previousItem = "";

		SendMyMailRadioButton_OnClick(1);
		SendMyMailCODButton:Disable();
		SendMyMailCODButtonText:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b);
	end
	-- Update the cost
	MoneyFrame_Update("SendMyMailCostMoneyFrame", GetSendMailPrice());	
	
	-- Color the postage text
	if ( GetSendMailPrice() > GetMoney() ) then
		SetMoneyFrameColor("SendMyMailCostMoneyFrame", "red");
	else
		SetMoneyFrameColor("SendMyMailCostMoneyFrame", "white");
	end

	-- Determine how many rows of attachments to show
	local itemRowCount = 1;
	local temp = last;
	while ((temp > ATTACHMENTS_PER_ROW_SEND) and (itemRowCount < ATTACHMENTS_MAX_ROWS_SEND)) do
		itemRowCount = itemRowCount + 1;
		temp = temp - ATTACHMENTS_PER_ROW_SEND;
	end
	if (not gap and (temp == ATTACHMENTS_PER_ROW_SEND) and (itemRowCount < ATTACHMENTS_MAX_ROWS_SEND)) then
		itemRowCount = itemRowCount + 1;
	end
	if (SendMyMailFrame.maxRowsShown and (last > 0) and (itemRowCount < SendMyMailFrame.maxRowsShown)) then
		itemRowCount = SendMyMailFrame.maxRowsShown;
	else
		SendMyMailFrame.maxRowsShown = itemRowCount;
	end

	-- Compute sizes
	local cursorx = 0;
	local cursory = itemRowCount - 1;
	local marginxl = 8 + 6;
	local marginxr = 40 + 6;
	local areax = SendMyMailFrame:GetWidth() - marginxl - marginxr;
	local iconx = SendMyMailAttachment1:GetWidth() + 2;
	local icony = SendMyMailAttachment1:GetHeight() + 2;
	local gapx1 = floor((areax - (iconx * ATTACHMENTS_PER_ROW_SEND)) / (ATTACHMENTS_PER_ROW_SEND - 1));
	local gapx2 = floor((areax - (iconx * ATTACHMENTS_PER_ROW_SEND) - (gapx1 * (ATTACHMENTS_PER_ROW_SEND - 1))) / 2);
	local gapy1 = 5;
	local gapy2 = 6;
	local areay = (gapy2 * 2) + (gapy1 * (itemRowCount - 1)) + (icony * itemRowCount);
	local indentx = marginxl + gapx2;
	local indenty = 170 + gapy2 + icony;
	local tabx = (iconx + gapx1) - 2; --this magic number changes the attachment spacing
	local taby = (icony + gapy1);
	local scrollHeight = 249 - areay;

	SendMyMailHorizontalBarLeft2:SetPoint("TOPLEFT", "SendMyMailFrame", "BOTTOMLEFT", 2, 184 + areay);
	SendMyStationeryBackgroundLeft:SetHeight(min(scrollHeight, 256));
	SendMyStationeryBackgroundLeft:SetTexCoord(0, 1.0, 0, min(scrollHeight, 256) / 256);
	SendMyStationeryBackgroundRight:SetHeight(min(scrollHeight, 256));
	SendMyStationeryBackgroundRight:SetTexCoord(0, 1.0, 0, min(scrollHeight, 256) / 256);
	SendMyStationeryBackgroundLeft:SetTexture("Interface/Stationery/stationerytest1");
	SendMyStationeryBackgroundRight:SetTexture("Interface/Stationery/stationerytest2");
	
	-- Set Items
	for i=1, ATTACHMENTS_MAX_SEND do
		if (cursory >= 0) then
			SendMyMailFrame.SendMyMailAttachments[i]:Enable();
			SendMyMailFrame.SendMyMailAttachments[i]:Show();
			SendMyMailFrame.SendMyMailAttachments[i]:SetPoint("TOPLEFT", "SendMyMailFrame", "BOTTOMLEFT", indentx + (tabx * cursorx), indenty + (taby * cursory));
			
			cursorx = cursorx + 1;
			if (cursorx >= ATTACHMENTS_PER_ROW_SEND) then
				cursory = cursory - 1;
				cursorx = 0;
			end
		else
			SendMyMailFrame.SendMyMailAttachments[i]:Hide();
		end
	end
	for i=ATTACHMENTS_MAX_SEND+1, ATTACHMENTS_MAX do
		SendMyMailFrame.SendMyMailAttachments[i]:Hide();
	end

	SendMyMailFrame_CanSend();
end

function SendMyMailFrame_Reset()
	SendMyMailNameEditBox:SetText("");
	SendMyMailNameEditBox:SetFocus();
	SendMyMailSubjectEditBox:SetText("");
	MyMailEditBox:SetText("");
	SendMyMailFrame_Update();
	MoneyInputFrame_ResetMoney(SendMyMailMoney);
	SendMyMailRadioButton_OnClick(1);
	SendMyMailFrame.maxRowsShown = 0;
end

function SendMyMailFrame_CanSend()
	local checks = 0;
	local checksRequired = 2;
	-- Has a sendee
	if ( #SendMyMailNameEditBox:GetText() > 0 ) then
		checks = checks + 1;
	end
	-- and has a subject
	if ( #SendMyMailSubjectEditBox:GetText() > 0 ) then
		checks = checks + 1;
	end
	-- check c.o.d. amount
	if ( SendMyMailCODButton:GetChecked() ) then
		checksRequired = checksRequired + 1;
		-- COD must be less than 10000 gold
		if ( MoneyInputFrame_GetCopper(SendMyMailMoney) > MAX_COD_AMOUNT * COPPER_PER_GOLD ) then
			if ( ENABLE_COLORBLIND_MODE ~= "1" ) then
				SendMyMailErrorCoin:Show();
			end
			SendMyMailErrorText:Show();			
		else
			SendMyMailErrorText:Hide();
			SendMyMailErrorCoin:Hide();
			checks = checks + 1;
		end
	end
	
	if ( checks == checksRequired ) then
		SendMyMailMailButton:Enable();
	else
		SendMyMailMailButton:Disable();
	end
end

function SendMyMailRadioButton_OnClick(index)
	if ( index == 1 ) then
		SendMyMailSendMoneyButton:SetChecked(true);
		SendMyMailCODButton:SetChecked(false);
		SendMyMailMoneyText:SetText(AMOUNT_TO_SEND);
	else
		SendMyMailSendMoneyButton:SetChecked(false);
		SendMyMailCODButton:SetChecked(true);
		SendMyMailMoneyText:SetText(COD_AMOUNT);
	end
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON);
end

function SendMyMailMoneyButton_OnClick()
	local cursorMoney = GetCursorMoney();
	if ( cursorMoney > 0 ) then
		local money = MoneyInputFrame_GetCopper(SendMyMailMoney);
		if ( money > 0 ) then
			cursorMoney = cursorMoney + money;
		end
		MoneyInputFrame_SetCopper(SendMyMailMoney, cursorMoney);
		DropCursorMoney();
	end
end

function SendMyMailAttachmentButton_OnClick(self, button)
	ClickSendMyMyMailItemButton(self:GetID(), button == "RightButton");
end

function SendMyMailAttachmentButton_OnDropAny()
	ClickSendMyMyMailItemButton();
end

function SendMyMailAttachment_OnEnter(self)
	local index = self:GetID();
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	if ( HasSendMailItem(index) ) then
		local hasCooldown, speciesID, level, breedQuality, maxHealth, power, speed, name = GameTooltip:SetSendMyMyMailItem(index);
		if(speciesID and speciesID > 0) then
			BattlePetToolTip_Show(speciesID, level, breedQuality, maxHealth, power, speed, name);
		end
	else
		GameTooltip:SetText(ATTACHMENT_TEXT, 1.0, 1.0, 1.0);
	end
	self.UpdateTooltip = SendMyMailAttachment_OnEnter;
end

-----------------------------------------------------------------------------------------------
---------------------------------------- Open All Mail ----------------------------------------
-----------------------------------------------------------------------------------------------

local OPEN_ALL_MAIL_MIN_DELAY = 0.15;

MyOpenAllMailMixin = {};

function MyOpenAllMailMixin:Reset()
	self.mailIndex = 1;
	self.attachmentIndex = ATTACHMENTS_MAX;
	self.timeUntilNextRetrieval = nil;
	self.blacklistedItemIDs = nil;
end

function MyOpenAllMailMixin:StartOpening()
	self:Reset();
	self:Disable();
	self:SetText(OPEN_ALL_MAIL_BUTTON_OPENING);
	self:RegisterEvent("MAIL_INBOX_UPDATE");
	self:RegisterEvent("MAIL_FAILED");
	self.numToOpen = GetInboxNumItems();
	self:AdvanceAndProcessNextItem();
end

function MyOpenAllMailMixin:StopOpening()
	self:Reset();
	self:Enable();
	self:SetText(OPEN_ALL_MAIL_BUTTON);
	self:UnregisterEvent("MAIL_INBOX_UPDATE");
	self:UnregisterEvent("MAIL_FAILED");
end

function MyOpenAllMailMixin:AdvanceToNextItem()
	local foundAttachment = false;
	while ( not foundAttachment ) do
		local _, _, _, _, money, CODAmount, daysLeft, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(self.mailIndex);
		local itemID = select(2, GetInboxItem(self.mailIndex, self.attachmentIndex));
		local hasBlacklistedItem = self:IsItemBlacklisted(itemID);
		local hasCOD = CODAmount and CODAmount > 0;
		local hasMoneyOrItem = C_Mail.HasInboxMoney(self.mailIndex) or HasInboxItem(self.mailIndex, self.attachmentIndex);
		if ( not hasBlacklistedItem and not hasCOD and hasMoneyOrItem ) then
			foundAttachment = true;
		else
			self.attachmentIndex = self.attachmentIndex - 1;
			if ( self.attachmentIndex == 0 ) then
				break;
			end
		end
	end
	
	if ( not foundAttachment ) then
		self.mailIndex = self.mailIndex + 1;
		self.attachmentIndex = ATTACHMENTS_MAX;
		if ( self.mailIndex > GetInboxNumItems() ) then
			return false;
		end
		
		return self:AdvanceToNextItem();
	end
	
	return true;
end

function MyOpenAllMailMixin:AdvanceAndProcessNextItem()
	if ( CalculateTotalNumberOfFreeBagSlots() == 0 ) then
		self:StopOpening();
		return;
	end
	
	if ( self:AdvanceToNextItem() ) then
		self:ProcessNextItem();
	else
		self:StopOpening();
	end
end

function MyOpenAllMailMixin:ProcessNextItem()
	local _, _, _, _, money, CODAmount, daysLeft, itemCount, _, _, _, _, isGM = GetInboxHeaderInfo(self.mailIndex);
	if ( isGM or (CODAmount and CODAmount > 0) ) then
		self:AdvanceAndProcessNextItem();
		return;
	end
	
	if ( money > 0 ) then
		TakeInboxMoney(self.mailIndex);
		self.timeUntilNextRetrieval = OPEN_ALL_MAIL_MIN_DELAY;
	elseif ( itemCount and itemCount > 0 ) then
		TakeInboxItem(self.mailIndex, self.attachmentIndex);
		self.timeUntilNextRetrieval = OPEN_ALL_MAIL_MIN_DELAY;
	else
		self:AdvanceAndProcessNextItem();
	end
end

function MyOpenAllMailMixin:OnLoad()
	self:Reset();
end

function MyOpenAllMailMixin:OnEvent(event, ...)
	if event == "MAIL_INBOX_UPDATE" then
		if ( self.numToOpen ~= GetInboxNumItems() ) then
			self.mailIndex = 1;
			self.attachmentIndex = ATTACHMENTS_MAX;
		end
	elseif ( event == "MAIL_FAILED" ) then
		local itemID = ...;
		if ( itemID ) then
			self:AddBlacklistedItem(itemID);
		end
	end
end

function MyOpenAllMailMixin:OnUpdate(dt)
	if ( self.timeUntilNextRetrieval ) then
		self.timeUntilNextRetrieval = self.timeUntilNextRetrieval - dt;
		
		if ( self.timeUntilNextRetrieval <= 0 ) then
			if ( not C_Mail.IsCommandPending() ) then
				self.timeUntilNextRetrieval = nil;
				self:AdvanceAndProcessNextItem();
			else
				-- Delay until the current mail command is done processing.
				self.timeUntilNextRetrieval = OPEN_ALL_MAIL_MIN_DELAY;
			end
		end
	end
end

function MyOpenAllMailMixin:OnClick()
	self:StartOpening();
end

function MyOpenAllMailMixin:OnHide()
	self:StopOpening();
end

function MyOpenAllMailMixin:AddBlacklistedItem(itemID)
	if ( not self.blacklistedItemIDs ) then
		self.blacklistedItemIDs = {};
	end
	
	self.blacklistedItemIDs[itemID] = true;
end

function MyOpenAllMailMixin:IsItemBlacklisted(itemID)
	return self.blacklistedItemIDs and self.blacklistedItemIDs[itemID];
end

function SendMyMailEditBox_OnLoad()
	ScrollUtil.RegisterScrollBoxWithScrollBar(MyMailEditBox.ScrollBox, MyMailEditBoxScrollBar);
	MyMailEditBox:RegisterCallback("OnTabPressed", SendMyMailEditBox_OnTabPressed, MyMailEditBox);
end

function SendMyMailEditBox_OnTabPressed(self)
	EditBox_HandleTabbing(self, SEND_MY_MAIL_TAB_LIST);
end