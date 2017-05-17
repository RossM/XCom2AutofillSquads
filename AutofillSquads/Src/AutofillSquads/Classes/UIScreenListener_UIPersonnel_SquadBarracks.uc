class UIScreenListener_UIPersonnel_SquadBarracks extends UIScreenListener config(AutofillSquads);

var UIButton AutofillButton;
var UIPersonnel_SquadBarracks SquadPicker;

var localized string strAutofill;

var config int MaxSquadSize;

event OnInit(UIScreen Screen)
{
	SquadPicker = UIPersonnel_SquadBarracks(Screen);

	AutofillButton = SquadPicker.Spawn(class'UIButton', SquadPicker.UpperContainer);
	AutofillButton.InitButton(, strAutofill, OnAutofillClicked).SetPosition(566, 94);
}

function OnAutofillClicked(UIButton Button)
{
	local XComGameState_LWSquadManager SquadMgr;
	local XComGameState_LWPersistentSquad SquadState;

	SquadMgr = class'XComGameState_LWSquadManager'.static.GetSquadManager();

	if (SquadPicker.CurrentSquadSelection >= 0)
	{
		SquadState = SquadMgr.GetSquad(SquadPicker.CurrentSquadSelection);
		if (SquadState.bOnMission)
			return;

		AutofillSquad(SquadState);

		SquadPicker.bViewUnassignedSoldiers = false;
		SquadPicker.RefreshAllData();
	}
}

function AutofillSquad(XComGameState_LWPersistentSquad SquadState)
{
	local XComGameStateHistory History;
	local XComGameState NewGameState;
	local XComGameState_LWSquadManager SquadMgr;
	local array<XComGameState_Unit> SquadSoldiers;
	local array<StateObjectReference> UnassignedSoldiers;
	local array<XComGameState_Unit_LWOfficer> SquadOfficers;
	local XComGameState_Unit UnitState, BestUnitState;
	local StateObjectReference UnitRef;
	local int Missions, BestMissions;
	local int UnitsOfClass, BestUnitsOfClass;
	local int Rank, BestRank;
	local int UnassignedOfficers;
	local float OfficerDensity;

	History = `XCOMHISTORY;

	SquadMgr = class'XComGameState_LWSquadManager'.static.GetSquadManager();

	SquadSoldiers = SquadState.GetSoldiers();
	UnassignedSoldiers = SquadMgr.GetUnassignedSoldiers();

	foreach SquadSoldiers(UnitState)
	{
		if (class'LWOfficerUtilities'.static.IsOfficer(UnitState))
			SquadOfficers.AddItem(class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState));
	}

	NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Transferring Soldier");
	SquadState = XComGameState_LWPersistentSquad(NewGameState.CreateStateObject(class'XComGameState_LWPersistentSquad', SquadState.ObjectID));
	NewGameState.AddStateObject(SquadState);

	foreach UnassignedSoldiers(UnitRef)
	{
		UnitState = XComGameState_Unit(History.GetGameStateForObjectID(UnitRef.ObjectID));
		if (class'LWOfficerUtilities'.static.IsOfficer(UnitState))
			UnassignedOfficers++;
	}
	OfficerDensity = float(UnassignedOfficers) / UnassignedSoldiers.Length;

	while (SquadSoldiers.Length < default.MaxSquadSize)
	{
		BestUnitState = none;
		BestMissions = -1;
		BestUnitsOfClass = 999;
		BestRank = 0;

		foreach UnassignedSoldiers(UnitRef)
		{
			// Skip soldiers which can't be assigned to this squad now
			if (!SquadPicker.CanTransferSoldier(UnitRef, SquadState))
				continue;

			// Skip soldiers already added to the squad in an earlier iteration
			if (SquadState.SquadSoldiers.Find('ObjectID', UnitRef.ObjectID) != INDEX_NONE)
				continue;

			UnitState = XComGameState_Unit(History.GetGameStateForObjectID(UnitRef.ObjectID));

			// Skip officers equal or higher in rank than the current highest-rank officer
			if (class'LWOfficerUtilities'.static.IsOfficer(UnitState) && IsHigherRankingOfficer(UnitState, SquadOfficers))
				continue;

			Missions = GetMissionsUnderOfficers(UnitState, SquadOfficers);
			UnitsOfClass = GetUnitsOfClass(UnitState.GetSoldierClassTemplateName(), SquadSoldiers);
			Rank = UnitState.GetSoldierRank();

			if (class'LWOfficerUtilities'.static.IsOfficer(UnitState))
			{
				// If there are no officers, prefer the highest ranking officer. If there are too many officers, prefer non-officers.
				if (SquadOfficers.Length == 0)
					Missions = class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState).GetOfficerRank();
				else if (SquadOfficers.Length >= OfficerDensity * SquadSoldiers.Length)
					Missions = -1;
			}

			if ((Missions > BestMissions) ||
				(Missions == BestMissions && UnitsOfClass < BestUnitsOfClass) ||
				(Missions == BestMissions && UnitsOfClass == BestUnitsOfClass && Rank > BestRank))
			{
				BestUnitState = UnitState;
				BestMissions = Missions;
				BestUnitsOfClass = UnitsOfClass;
				BestRank = Rank;
			}
		}

		if (BestUnitState == none)
			break;

		`Log("Autofill: Adding" @ BestUnitState.GetFullName() @ "(Missions/Officer =" @ BestMissions $ ", Class =" @ BestUnitsOfClass $ ", Rank =" @ BestRank $ ")");

		SquadState.AddSoldier(BestUnitState.GetReference());
		SquadSoldiers.AddItem(BestUnitState);

		if (class'LWOfficerUtilities'.static.IsOfficer(BestUnitState))
			SquadOfficers.AddItem(class'LWOfficerUtilities'.static.GetOfficerComponent(BestUnitState));
	}

	if (NewGameState.GetNumGameStateObjects() > 0)
		`GAMERULES.SubmitGameState(NewGameState);
	else
		History.CleanupPendingGameState(NewGameState);
}

function int GetMissionsUnderOfficers(XComGameState_Unit UnitState, array<XComGameState_Unit_LWOfficer> SquadOfficers)
{
	local XComGameState_Unit_LWOfficer OfficerState;
	local LeadershipEntry Entry;
	local int Missions;

	foreach SquadOfficers(OfficerState)
	{
		foreach OfficerState.LeadershipData(Entry)
		{
			if (Entry.UnitRef.ObjectID == UnitState.ObjectID)
				Missions += Entry.SuccessfulMissionCount;
		}
	}

	return Missions;
}

function int GetUnitsOfClass(name TemplateName, array<XComGameState_Unit> SquadSoldiers)
{
	local XComGameState_Unit UnitState;
	local int Count;

	foreach SquadSoldiers(UnitState)
	{
		if (UnitState.GetSoldierClassTemplateName() == TemplateName)
			Count++;
	}

	return Count;
}

function bool IsHigherRankingOfficer(XComGameState_Unit UnitState, array<XComGameState_Unit_LWOfficer> SquadOfficers)
{
	local XComGameState_Unit_LWOfficer NewOfficer, CurrentOfficer;

	NewOfficer = class'LWOfficerUtilities'.static.GetOfficerComponent(UnitState);

	foreach SquadOfficers(CurrentOfficer)
	{
		if (NewOfficer.GetOfficerRank() >= CurrentOfficer.GetOfficerRank())
			return true;
	}

	return false;
}

defaultproperties
{
	ScreenClass = "UIPersonnel_SquadBarracks"
}