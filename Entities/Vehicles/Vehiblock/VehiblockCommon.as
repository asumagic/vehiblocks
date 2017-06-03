#include "VehiblockBlock.as"

// CONST GLOBAL PROPERTIES
const string blobFieldPrefix = "Vb@", // Vehiblock blob field prefix
			 blobFieldData = blobFieldPrefix + "d";

// VEHICLE DATA GLOBAL PROPERTIES
class VehiblockData
{
	// Internal algorithm variables
 	int nextShapeID = 0,
		nextLayerID = 0;

	bool insertedBlockLastTick = false;

	// Blocks (2D grid as a 1D array)
 	Block[] placedBlocks(vehiblockSize * vehiblockSize);

 	PlannedBlock[] toInsert;
 	RemovedBlock@[] toRemove;

	float massWeightSum = 7000.f;
	Vec2f centerOfMass = Vec2f_zero;

	// Queue a new block to be inserted
	void insert(int type, int offset)
	{
		toInsert.push_back(PlannedBlock(type, offset));
	}

	// Queue a block to be removed
	void remove(int offset)
	{
		toRemove.push_back(RemovedBlock(@placedBlocks[offset], offset));
	}

	void addMass(CShape@ shape, Vec2f position, const float blockMass)
	{
		float oldWeightSum = massWeightSum;
		massWeightSum += blockMass;

		centerOfMass = ((centerOfMass * oldWeightSum) + (position * blockMass)) / massWeightSum;
		shape.SetCenterOfMassOffset(centerOfMass);
		shape.SetMass(massWeightSum);

		print("New center of mass is (" + centerOfMass.x + "; " + centerOfMass.y + ") and mass " + massWeightSum);
	}

	// The "unsafe" methods exists because of the KAG engine bug - https://forum.thd.vg/threads/obscure-cshape-removeshape-method.26842/#post-398411
	// This bug makes using both RemoveShape and AddShape within a tick unreliable.
	// As a workaround vehiblock exposes a toInsert and a toRemove list. When/if this bug gets fixed it can be done directly again.
	void unsafe_remove(CBlob@ blob, const RemovedBlock rblock)
	{
		Block@ block = rblock.block;
		print("Unsafe remove block type " + block.type + ", shapeID " + block.shapeID + ", layerID " + block.layerID + " at tick " + getGameTime());
		CShape@ shape = blob.getShape();
		shape.RemoveShape(block.shapeID);

		// TODO this could be done faster by sorting the array first
		for (int i = 0; i < toRemove.size(); i++)
		{
			if (toRemove[i].block.shapeID > block.shapeID)
			{
				--toRemove[i].block.shapeID;
			}
		}

		// Align other shapeIDs to the current one
		for (int i = 0; i < placedBlocks.size(); i++)
		{
			if (placedBlocks[i].shapeID > block.shapeID)
			{
				--placedBlocks[i].shapeID;
			}
		}

		blob.getSprite().RemoveSpriteLayer("t" + block.layerID);
		addMass(shape, BlockPosition(rblock.offset).toVec(), -1000.f);
		--nextShapeID;
		block.type = 0;
	}

	void unsafe_insert(CBlob@ blob, const BlockPosition position, const u16 tile)
	{
		if (placedBlocks[position.absolute()].isPresent())
		{
			remove(position.absolute());
		}

		// Add the shape and the sprite layer
		CShape@ shape = blob.getShape();

		// TODO optimize the shape so we don't get just tons of useless vertices. but it's gonna be a pain with the removeshape stuff...
		const float tileSize = getMap().tilesize;
		const int facing = (blob.isFacingLeft() ? -1 : 1),
				  facingCompensation = (blob.isFacingLeft() ? -tileSize : 0);
		Vec2f rectTL = Vec2f(facing * ((position.x * tileSize) - (tileSize / 2.f)) + facingCompensation, (position.y * tileSize) - (tileSize / 2.f));
		Vec2f[] tileRect =
		{
			Vec2f(rectTL.x, rectTL.y),
			Vec2f(rectTL.x + tileSize, rectTL.y),
			Vec2f(rectTL.x + tileSize, rectTL.y + tileSize),
			Vec2f(rectTL.x, rectTL.y + tileSize)
		};
		shape.AddShape(tileRect);

		// TODO handle damage levels
		CSpriteLayer@ spriteLayer = blob.getSprite().addSpriteLayer("t" + ++nextLayerID, "world.png", 8, 8);
		spriteLayer.SetOffset(position.toVec());
		spriteLayer.SetFrameIndex(tile);

		placedBlocks[position.absolute()] = Block(tile, ++nextShapeID, nextLayerID);

		addMass(shape, position.toVec(), 1000.f);

		Block@ block = placedBlocks[position.absolute()];
		print("Unsafe insert block type " + block.type + ", shapeID " + block.shapeID + ", layerID " + block.layerID + " at tick " + getGameTime());
	}

};

VehiblockData vData;

bool isBuildableAt(const BlockPosition position)
{
	return ((position.x == 0) && (position.y == 0)) || // is core block
		   (vData.placedBlocks[BlockPosition(position.x, position.y - 1).absolute()].isPresent()) || // is top present
		   (vData.placedBlocks[BlockPosition(position.x + 1, position.y).absolute()].isPresent()) || // is right present
		   (vData.placedBlocks[BlockPosition(position.x, position.y + 1).absolute()].isPresent()) || // is bottom present
		   (vData.placedBlocks[BlockPosition(position.x - 1, position.y).absolute()].isPresent());   // is left present
}

BlockPosition positionFromWorldPos(CBlob@ blob, const Vec2f blockPosition)
{
	const Vec2f blobPosition = blob.getPosition();
	const float tileSize = getMap().tilesize;
	Vec2f flat((blockPosition.x - blobPosition.x) / tileSize, (blockPosition.y - blobPosition.y) / tileSize);
	flat.RotateBy(-blob.getAngleDegrees());

	return BlockPosition(flat);
}

void syncFromBlob(CBlob@ blob)
{
	blob.get(blobFieldData, vData);
}

void syncToBlob(CBlob@ blob)
{
	blob.set(blobFieldData, vData);
}
