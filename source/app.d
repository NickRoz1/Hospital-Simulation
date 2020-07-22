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

/// @brief Amount of ticks in one minute.
const size_t TICKS_MINUTE = 60;

/// @brief Amount of ticks in one hour.
const size_t TICKS_HOUR = TICKS_MINUTE * 60;

/// @brief Duration of work shift for hospital personnel.
const size_t SHIFT_DURATION = 8 * TICKS_HOUR;

/// @brief Duration of minimal stay duration.
const size_t MIN_STAY_DUR = TICKS_MINUTE;

/// @brief Type of agents in hospital
enum AgentType
{
	DOCTOR,
	NURSE,
	VISITOR,
	PATIENT
};

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
		Cell currCell = scheduleQueue.front[0];
		const size_t stayDur = scheduleQueue.front[1];
		if (timeInCurrCell < stayDur)
			return;
		currCell.leaveCell(this);
		scheduleQueue.removeFront();
		currCell = scheduleQueue.front[0];
		currCell.enterCell(this);
	}

	/// @brief Returns false if no more schedulable time left.
	bool isSchedulable()
	{
		assert(notScheduledTime >= 0);
		return notScheduledTime != 0;
	}
	/// @brief Time not scheduled yet.
	size_t notScheduledTime;

	/// @brief Time spent in current cell;
	size_t timeInCurrCell;

	/// @brief Convenience alias of (Cell, Duration) pair (tuple).
	alias CellDurPair = Tuple!(Cell, size_t);

	/// @brief Agent schedule queue. Consists of Cell reference and Duration variable.
	/// every time timeInCurrCell becomes equal to Duration variable, schedule pops front,
	/// the agent enlists into the next scheduled cell, flushes timeInCurrCell variable.
	///
	/// @note Filled on scheduling stage started from Hospital constructor.
	DList!(CellDurPair) scheduleQueue;
}

interface SchedulableAgent
{
	/// @brief Schedule visit to cell. Returns scheduled duration of visit.
	size_t schedule(Cell cell, size_t requestedTime);

	/// @brief Helper function to avoid code duplication. 
	/// @note Generates stay duration and decreases amount of notScheduledTime
	final size_t scheduleImpl(size_t maxStayDur, ref size_t notScheduledTime, size_t requestedTime)
	{
		const size_t cappedStayDur = min(notScheduledTime, maxStayDur);
		const size_t durOfVisit = uniform!"[]"(0, cappedStayDur);
		notScheduledTime -= durOfVisit;
		return durOfVisit;
	}
}

/// @brief Doctor class. Visits subset of hospital sets every hour.
class Nurse : Agent, SchedulableAgent
{
public:
	this()
	{
		notScheduledTime = SHIFT_DURATION;
	}

	override size_t schedule(Cell cell, size_t requestedTime)
	{
		const size_t stayDur = scheduleImpl(maxStayDuration[AgentType.NURSE],
				notScheduledTime, requestedTime);
		auto cellDurPair = CellDurPair(cell, stayDur);
		scheduleQueue.insertBack(cellDurPair);
		return stayDur;
	}
}

/// @brief Doctor class. Visits subset of hospital sets once a day.
class Doctor : Agent, SchedulableAgent
{
	this()
	{
		notScheduledTime = SHIFT_DURATION;
	}

	override size_t schedule(Cell cell, size_t requestedTime)
	{
		const size_t stayDur = scheduleImpl(maxStayDuration[AgentType.DOCTOR],
				notScheduledTime, requestedTime);
		auto cellDurPair = CellDurPair(cell, stayDur);
		scheduleQueue.insertBack(cellDurPair);
		return stayDur;
	}
}

/// @brief Visitor class. Visit one cell 2-3 times a day.
class Visitor : Agent, SchedulableAgent
{
	this()
	{
		notScheduledTime = TICKS_HOUR;
	}

	override size_t schedule(Cell cell, size_t requestedTime)
	{
		const size_t stayDur = scheduleImpl(maxStayDuration[AgentType.VISITOR],
				notScheduledTime, requestedTime);
		auto cellDurPair = CellDurPair(cell, stayDur);
		scheduleQueue.insertBack(cellDurPair);
		return stayDur;
	}
}

/// @brief Patients class. Exists only in boundaries of it's cell.
class Patient : Agent
{
	override void tick()
	{
		/// @note Patients are staying inside cell.
	}
}

/// @brief Hospital cell. Represent area where patients live and other 
/// agents gather through time. Each cell requires 6 hours of nurse and
/// 1.5 hours of doctors presence through day.
class Cell
{
public:

	/// @brief Cell ID
	const size_t id;

	/// @brief Create cell with `patientNum` patients inside
	this(const size_t patientNum, const size_t cellId)
	{
		id = cellId;
		Patient[] patients;
		patients.length = patientNum;
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
	void tick(bool performLog = false)
	{
		foreach (ref agent; agents.byKey())
		{
			agent.tick();
		}
		if (performLog)
			logState();
	}

	/// @brief Logs agents located in the currect cell.
	void logState()
	{
		writeln("Cell " ~ to!string(id) ~ " contains:");
		foreach (ref agent; agents.byKey())
		{
			writeln("   " ~ agent.id.toString());
		}
	}

	/// @brief Returns amount of time certain type of agents must
	/// spend within cell throughout the day.
	static size_t getAgentPresenceTime(AgentType agentT)
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
	this(size_t size)
	{
		size_t[] patientNums;
		patientNums.length = size;
		const size_t minPatientNum = 2;
		foreach (i; 0 .. size)
		{
			/// @note number of patients in cell 2-4
			patientNums[i] = minPatientNum + uniform!"[]"(0, 2);
		}

		this(patientNums);
	}

	/// @brief Create hospital with patientNums.length cells occupied with
	/// corresponding number of patients specified in patientNums
	this(size_t[] patientNums)
	{
		_cells.length = patientNums.length;
		foreach (i; 0 .. patientNums.length)
		{
			_cells[i] = new Cell(patientNums[i], i);
		}
	}

	/// @brief Process next tick
	/// @note Each time tick triggered, all underlying cells trigger their tick
	/// method too. When the cell is triggered all agents in it determine their
	/// renewed status (whether they ran out of their time in their cell) and leave
	/// or enter cells. After agents finished their actions, and if certain amount of
	/// time since last log passed, cell logs every agent left in it. 
	void tick()
	{
		foreach (ref cell; _cells)
		{
			/// @note Trigger cell.logState() once in 30 ticks
			if (currTick % 30 == 0)
				cell.tick(true);
			else
				cell.tick();
		}
		currTick += 1;
	}

	/// @brief Current tick
	size_t currTick = 0;

private:
	/// @brief Associate personnel with cells (create cells schedule)
	/// @note First, the number of personnel required to serve every
	/// cell in hospital calculated (using each cell required presence time).
	/// After that, personnel is randomly created and distributed so each worker will
	/// spend random time at each cell, yet the required presence time will
	/// be spent.
	void createSchedule()
	{
		size_t totalDoctorsHours = _cells.length * Cell.getAgentPresenceTime(AgentType.DOCTOR);
		size_t totalNursesHours = _cells.length * Cell.getAgentPresenceTime(AgentType.NURSE);
		size_t totalVisitorHours = _cells.length * Cell.getAgentPresenceTime(AgentType.VISITOR); /// @note Assuming that hospital is fully personnel-equipped
		/// The result of division ceiled. Some personnel could be not
		/// fully occupied.
		auto calcPersonnelCount = (size_t totalHours) => cast(size_t) ceil(
				totalHours / cast(double) SHIFT_DURATION);
		const size_t numberOfDoctors = calcPersonnelCount(totalDoctorsHours);
		const size_t numberOfNurses = calcPersonnelCount(totalNursesHours);
		const size_t numberOfVisitors = calcPersonnelCount(totalVisitorHours);
		T[] genArray(T)(size_t len)
		{
			T[] t;
			t.length = len;
			return t;
		}

		_doctors ~= genArray!(Doctor)(numberOfDoctors);
		_nurses ~= genArray!(Nurse)(numberOfDoctors);
		_visitors ~= genArray!(Visitor)(numberOfDoctors);
		foreach (ref cell; _cells)
		{
			distributePersonnel(cell, AgentType.DOCTOR, totalDoctorsHours, _doctors);
			distributePersonnel(cell, AgentType.NURSE, totalNursesHours, _nurses);
			distributePersonnel(cell, AgentType.VISITOR, totalVisitorHours, _visitors);
		}
	}

	/// @brief Create cell schedule
	void distributePersonnel(AgentArr)(Cell cell, AgentType agentT,
			ref size_t totalWorkTime, AgentArr[] agentArr)
	{
		size_t requestedTime = Cell.getAgentPresenceTime(agentT);

		/// @note Circular range to be iterated over till the cell
		/// time presence requirement will be fullfilled.
		auto agentCircularRange = cycle(agentArr[0 .. $]); /// @note while the cell presence time is not complitely scheduled,
		/// continue scheduling personnel (agentArr contents) to this cell.
		while (requestedTime > 0)
		{
			/// @brief Schedule personell for random duration (in specified boundaries)
			/// until requested time is fullfilled.
			auto currentAgent = agentCircularRange.front();
			const size_t stayDur = currentAgent.schedule(cell, requestedTime);
			requestedTime -= stayDur;
		}
	}

	/// @brief Hospital model consists of cells. Each cell may contain certain
	/// amount of people at a time.
	Cell[] _cells;
	Doctor[] _doctors;
	Nurse[] _nurses;
	Visitor[] _visitors;
}

void main()
{
	Hospital hospital = new Hospital(500);
	size_t duration = 24 * TICKS_HOUR;

	while (duration > 0)
	{
		hospital.tick();
		--duration;
	}
}
