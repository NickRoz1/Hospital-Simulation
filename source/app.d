import std.stdio;
import std.range;
import std.random;
import std.algorithm;
import std.math;
import std.typecons;
import std.container : DList;
import std.container.rbtree;
import std.uuid;
import std.conv;
import std.datetime;
import std.range.interfaces;
import std.json;
import std.file;

/// @brief Amount of ticks in one minute.
const long TICKS_MINUTE = 60;

/// @brief Amount of ticks in one hour.
const long TICKS_HOUR = TICKS_MINUTE * 60;

/// @brief Duration of work shift for hospital personnel.
const long SHIFT_DURATION = 8 * TICKS_HOUR;

/// @brief Duration of minimal stay duration.
const long MIN_STAY_DUR = TICKS_MINUTE;

/// @brief Current time
auto currTime = DateTime(2020, 7, 27);

/// @brief Type of agents in hospital
enum AgentType
{
	DOCTOR,
	NURSE,
	VISITOR,
	PATIENT
};

void fillArray(T)(T[] arr)
{
	foreach (i; 0 .. arr.length)
	{
		arr[i] = new T();
	}
}

/// @brief Maximum stay at cell duration for different types of agents.
enum maxStayDuration = [
		AgentType.DOCTOR : 30 * TICKS_MINUTE, AgentType.NURSE : TICKS_HOUR,
		AgentType.VISITOR : TICKS_HOUR
	];

/// @brief Agent base class. Agent is one of a hospital residents.
abstract class Agent
{

	/// @brief Constructs Agent from array of time periods agent 
	/// is scheduled to work during the day.
	this()
	{
		id = randomUUID();
	}

	/// @brief Agent ID
	const UUID id;

	/// @brief Process next tick.
	void tick()
	{
		if (finished)
			return;
		Cell currCell = scheduleQueue.front[0];
		const long stayDur = scheduleQueue.front[1];
		timeInCurrCell++;
		// writeln("LOL");
		// writeln(timeInCurrCell)
		if (timeInCurrCell < stayDur)
			return;
		// writeln("EXACTLY!" ~ this.toString());
		currCell.leaveCell(this);
		scheduleQueue.removeFront();
		if (scheduleQueue.empty)
		{
			finished = true;
			return;
		}
		currCell = scheduleQueue.front[0];
		currCell.enterCell(this);
	}

	/// @brief Returns false if no more schedulable time left.
	bool isSchedulable()
	{
		assert(notScheduledTime >= 0);
		return notScheduledTime >= 0;
	}
	/// @brief Time not scheduled yet.
	long notScheduledTime = SHIFT_DURATION;

	/// @brief Time spent in current cell;
	long timeInCurrCell;

	/// @brief Convenience alias of (Cell, Duration) pair (tuple).
	alias CellDurPair = Tuple!(Cell, long);

	bool finished = false;

	/// @brief Agent schedule queue. Consists of Cell reference and Duration variable.
	/// every time timeInCurrCell becomes equal to Duration variable, schedule pops front,
	/// the agent enlists into the next scheduled cell, flushes timeInCurrCell variable.
	///
	/// @note Filled on scheduling stage started from Hospital constructor.
	DList!(CellDurPair) scheduleQueue;

	string toStringSchedule()
	{
		string str = "Schedule ";
		foreach (pair; scheduleQueue)
		{
			str ~= "\n    Cell:" ~ to!string(pair[0].id);
			str ~= "\n    Time:" ~ to!string(pair[1]);
		}
		return str;
	}
}

/// @brief Mixin for common functionality for agents which have schedule
mixin template SchedulableAgent(AgentType agentT)
		if (AgentType.min <= agentT && agentT <= AgentType.max)
{
	/// @brief Schedule visit to cell. Returns scheduled duration of visit.
	final long schedule(Cell cell, long requestedTime, long delayToFirst)
	{
		bool isFirstCell = scheduleQueue.empty;
		CellDurPair cellDurPair;
		const long stayDur = scheduleImpl(maxStayDuration[agentT], notScheduledTime, requestedTime);
		if (isFirstCell)
		{
			/// @note Create dummy cell to wait in till the delay to the first cell passes.
			/// Nurse room may be introduced later.
			cellDurPair = CellDurPair(new Cell(0, -1), delayToFirst);
		}
		else
		{
			cellDurPair = CellDurPair(cell, stayDur);
		}
		Cell previousCell;
		if (!isFirstCell && (previousCell = scheduleQueue.back[0]) == cell)
		{
			auto dur = scheduleQueue.back[1];
			dur += stayDur;
		}
		else
		{
			scheduleQueue.insertBack(cellDurPair);
		}
		return stayDur;
	}

	/// @brief Helper function to avoid code duplication. 
	/// @note Generates stay duration and decreases amount of notScheduledTime
	final long scheduleImpl(long maxStayDur, ref long notScheduledTime, long requestedTime)
	{
		const long minDurOfVisit = min(notScheduledTime, TICKS_MINUTE, requestedTime);
		const long cappedStayDur = min(notScheduledTime, maxStayDur, requestedTime);
		const long durOfVisit = uniform!"[]"(0, cappedStayDur);
		notScheduledTime -= durOfVisit;
		return durOfVisit;
	}
}

/// @brief Doctor class. Visits subset of hospital sets every hour.
class Nurse : Agent
{
public:
	mixin SchedulableAgent!(AgentType.NURSE);

	/// @brief Get string representation
	override string toString() const
	{
		return id.toString();
	}
}

/// @brief Doctor class. Visits subset of hospital sets once a day.
class Doctor : Agent
{
public:
	mixin SchedulableAgent!(AgentType.DOCTOR);

	/// @brief Get string representation
	override string toString()
	{
		return id.toString();
	}
}

/// @brief Visitor class. Visits one cell 2-3 times a day.
class Visitor : Agent
{
public:
	mixin SchedulableAgent!(AgentType.VISITOR);

	this()
	{
		notScheduledTime = TICKS_HOUR;
	}

	/// @brief Get string representation
	override string toString() const
	{
		return id.toString();
	}
}

/// @brief Patients class. Exists only in boundaries of it's cell.
class Patient : Agent
{
	/// @brief Get string representation
	override string toString() const
	{
		return id.toString();
	}
}

/// @brief Hospital cell. Represent area where patients live and other 
/// agents gather through time. Each cell requires 6 hours of nurse and
/// 1.5 hours of doctors presence through day.
class Cell
{
public:

	/// @brief Cell ID
	const long id;

	/// @brief Create cell with `patientNum` patients inside
	this(const long patientNum, const long cellId)
	{
		id = cellId;
		Patient[] patients;
		patients.length = patientNum;
		fillArray(patients);
		foreach (ref patient; patients)
		{
			agents[patient] = true;
		}
	}

	/// @brief Registers agent in this cell
	void enterCell(Agent agent)
	{
		agents[agent] = true;
	}

	/// @brief Deletes agent registration in this cell
	void leaveCell(Agent agent)
	{
		agents.remove(agent);
	}

	/// @brief Process next tick
	void tick()
	{
		logState();
	}

	/// @brief Logs agents located in the currect cell.
	void logState()
	{
		logger(id, agents.byKey());
	}

	/// @brief Returns amount of time certain type of agents must
	/// spend within cell throughout the day.
	static long getAgentPresenceTime(AgentType agentT)
	{
		final switch (agentT)
		{
		case AgentType.DOCTOR:
			return TICKS_HOUR * 2;
		case AgentType.NURSE:
			return TICKS_HOUR * 8;
		case AgentType.PATIENT:
			return TICKS_HOUR * 24;
		case AgentType.VISITOR:
			return TICKS_HOUR * 3;
		}
	}

	/// @brief Hashset containing Agents currently located inside this cell.
	bool[Agent] agents;

}

/// @brief Hospital model
class Hospital
{
public:
	/// @brief Create hospital with `size` cells
	this(long size)
	{
		long[] patientNums;
		patientNums.length = size;
		const long minPatientNum = 2;
		foreach (i; 0 .. size)
		{
			/// @note number of patients in cell 2-4
			patientNums[i] = minPatientNum + uniform!"[]"(0, 2);
		}

		this(patientNums);
	}

	/// @brief Create hospital with patientNums.length cells occupied with
	/// corresponding number of patients specified in patientNums
	this(long[] patientNums)
	{
		_cells.length = patientNums.length;
		foreach (i; 0 .. patientNums.length)
		{
			_cells[i] = new Cell(patientNums[i], i);
		}
		createSchedule();
	}

	/// @brief Process next tick
	/// @note Each time tick triggered, all underlying cells trigger their tick
	/// method too. When the cell is triggered all agents in it determine their
	/// renewed status (whether they ran out of their time in their cell) and leave
	/// or enter cells. After agents finished their actions, and if certain amount of
	/// time since last log passed, cell logs every agent left in it. 
	void tick()
	{
		foreach (ref agent; roundRobin(cast(Agent[]) _doctors, cast(Agent[]) _nurses,
				cast(Agent[]) _visitors))
		{
			// writeln("Processing agent: " ~ agent.toString());
			agent.tick();
			// writeln(agent.toString());
			// writeln(agent.toStringSchedule());
		}
		if (currTick % 30 == 0)
		{
			currTime += 30.seconds;
			foreach (ref cell; _cells)
			{
				/// @note log agents in the cell.
				cell.tick();
			}

		}
		currTick += 1;
	}

	/// @brief Current tick
	long currTick = 0;

private:
	/// @brief Associate personnel with cells (create cells schedule)
	/// @note First, the number of personnel required to serve every
	/// cell in hospital calculated (using each cell required presence time).
	/// After that, personnel is randomly created and distributed so each worker will
	/// spend random time at each cell, yet the required presence time will
	/// be spent.
	void createSchedule()
	{
		long totalDoctorsHours = _cells.length * Cell.getAgentPresenceTime(AgentType.DOCTOR);
		long totalNursesHours = _cells.length * Cell.getAgentPresenceTime(AgentType.NURSE);
		long totalVisitorHours = _cells.length * Cell.getAgentPresenceTime(AgentType.VISITOR); /// @note Assuming that hospital is fully personnel-equipped
		/// The result of division ceiled. Some personnel could be not
		/// fully occupied.
		auto calcPersonnelCount = (long totalHours, long shiftDur) => cast(long) ceil(
				totalHours / cast(double) shiftDur);
		const long numberOfDoctors = calcPersonnelCount(totalDoctorsHours, SHIFT_DURATION);
		const long numberOfNurses = calcPersonnelCount(totalNursesHours, SHIFT_DURATION);
		const long numberOfVisitors = calcPersonnelCount(totalVisitorHours, TICKS_HOUR);

		_doctors.length = numberOfDoctors;
		_nurses.length = numberOfNurses;
		_visitors.length = numberOfVisitors;

		fillArray(_doctors);
		fillArray(_nurses);
		fillArray(_visitors);

		foreach (ref cell; _cells)
		{
			distributePersonnel(cell, AgentType.DOCTOR, totalDoctorsHours, _doctors);
			distributePersonnel(cell, AgentType.NURSE, totalNursesHours, _nurses);
			distributePersonnel(cell, AgentType.VISITOR, totalVisitorHours, _visitors);
		}
	}

	/// @brief Create cell schedule
	void distributePersonnel(AgentArr)(Cell cell, AgentType agentT,
			ref long totalWorkTime, AgentArr[] agentArr)
	{
		long requestedTime = Cell.getAgentPresenceTime(agentT);

		/// @note Circular range to be iterated over until the cell
		/// time presence requirement will be fullfilled.
		auto agentCircularRange = cycle(agentArr[0 .. $]);
		/// @note while the cell presence time is not complitely scheduled,
		/// continue scheduling personnel (agentArr contents) to this cell.
		long spentTime = 0;
		long delayTillFirst = 0;
		while (requestedTime > 0)
		{
			// writeln(requestedTime);
			/// @brief Schedule personell for random duration (in specified boundaries)
			/// until requested time is fullfilled.
			auto currentAgent = agentCircularRange.front();
			if (currentAgent.isSchedulable())
			{
				const long stayDur = currentAgent.schedule(cell, requestedTime, delayTillFirst);
				delayTillFirst = stayDur;
				requestedTime -= stayDur;
				spentTime += stayDur;
			}
			agentCircularRange.popFront();
		}
	}

	/// @brief Hospital model consists of cells. Each cell may contain certain
	/// amount of people at a time.
	Cell[] _cells;
	Doctor[] _doctors;
	Nurse[] _nurses;
	Visitor[] _visitors;
}

/// @brief Logger which is used by Cell to record its state
void logger(AgentArr)(const long id, AgentArr agents)
{

	// writeln("Cell " ~ to!string(id) ~ " at " ~ currTime.toSimpleString() ~ " contains:");
	// foreach (ref agent; agents)
	// {
	// 	writeln("   " ~ agent.toString());
	// }
	/// @note All agents in this cell are registered as by their phones.
	/// The expected generated log is all possible pairs of agents in this cell.
	foreach (ref agent1; agents)
	{
		foreach (ref agent2; agents)
		{
			if (agent1 == agent2)
				continue;

			JSONValue contact = [
				"agent_1" : agent1.toString(), "agent_2" : agent2.toString(),
				"timestamp" : SysTime(currTime, UTC()).toISOExtString()
			];

			jj.array ~= contact;

			// writeln(agent1.toString() ~ ' ' ~ agent2.toString() ~ ` ` ~ SysTime(currTime,
			// 		UTC()).toISOExtString());
		}
	}
}

JSONValue jj;

void main()
{
	jj = ["START OF FILE"]; // Can't create empty array

	Hospital hospital = new Hospital(1000);
	long duration = 24 * TICKS_HOUR;
	while (duration > 0)
	{
		hospital.tick();
		--duration;
	}

	std.file.write("contact_list", jj.toString());
}
